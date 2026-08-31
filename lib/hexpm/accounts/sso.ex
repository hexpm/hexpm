defmodule Hexpm.Accounts.SSO do
  use Hexpm.Context

  alias Hexpm.Accounts.SSO.{
    Authorization,
    Connection,
    Enforcement,
    Error,
    Failure,
    Features,
    Identity,
    OIDC,
    OrgSession
  }

  alias Hexpm.Accounts.SSO.OIDC.Issuer
  alias Hexpm.Accounts.SSO.Transaction, as: SSOTransaction
  alias Hexpm.Accounts.OrganizationUser
  alias Hexpm.Emails
  alias Hexpm.Emails.Outbox

  @transaction_lifetime_seconds 10 * 60
  @authorization_lifetime_seconds 10 * 60
  @authorization_organization_limit 20
  @diagnostic_limit 20
  @identity_linked_email_category "sso.identity_linked"
  @identity_unlinked_email_category "sso.identity_unlinked"
  @email_mismatch_category "sso.email_mismatch"
  @seats_exhausted_category "sso.seats_exhausted"
  # The notices an account takes with it, which are the ones enqueued under its
  # scope key.
  @notification_categories [
                             @identity_linked_email_category,
                             @identity_unlinked_email_category,
                             @email_mismatch_category
                           ] ++ Enforcement.member_notification_categories()
  # A seat notice is about the organization, not about the member who happened
  # to trip it, so unlinking that member must not cancel it.
  @cancelled_notification_categories [
    @identity_linked_email_category,
    @email_mismatch_category
  ]
  @seats_notice_seconds 60 * 60

  def available?, do: Features.available?()

  @doc """
  Whether this organization reaches the SSO screens and can authenticate
  against them.

  Configuring SSO takes an active subscription; keeping what you configured
  does not. A lapsed card must not leave a broken connection with no screen to
  repair it on, or leave members enforced with no way to sign in.
  """
  def reachable?(organization) do
    Features.enabled?(organization) or
      (Features.active?(organization) and not is_nil(get_connection(organization)))
  end

  def get_connection(organization, preload \\ []) do
    Repo.get_by(Connection, organization_id: organization.id)
    |> Repo.preload(preload)
  end

  def configure(organization, attrs, audit: audit_data) do
    connection = get_connection(organization) || %Connection{organization_id: organization.id}
    issuer = attrs |> value(:issuer) |> trim()
    client_id = attrs |> value(:client_id) |> trim()
    supplied_secret = attrs |> value(:client_secret) |> present()
    client_secret = supplied_secret || connection.client_secret

    attrs = %{
      organization_id: organization.id,
      issuer: issuer,
      client_id: client_id,
      client_secret: client_secret
    }

    cond do
      not Features.enabled?(organization) ->
        {:error, :feature_disabled}

      require_admin(organization, audit_data.user) != :ok ->
        {:error, :admin_required}

      Connection.enabled?(connection) ->
        {:error, :connection_enabled}

      identity_key_changed_with_identities?(connection, issuer, client_id) ->
        {:error, :connection_has_identities}

      true ->
        changeset = Connection.credentials_changeset(connection, attrs)

        with {:ok, connection} <- validate_changeset(changeset),
             {:ok, _uri} <- Issuer.validate_syntax(connection.issuer),
             {:ok, metadata} <- OIDC.impl().discover(connection.issuer) do
          persist_configuration(connection, supplied_secret, metadata, organization, audit_data)
        end
    end
  end

  defp persist_configuration(desired, supplied_secret, metadata, organization, audit_data) do
    with_locked_connection(organization, audit_data.user, &require_feature/1, fn current ->
      connection = current || %Connection{organization_id: organization.id, version: 0}

      if Connection.enabled?(connection) do
        Hexpm.RepoBase.rollback(:connection_enabled)
      end

      if identity_key_changed_with_identities?(connection, desired.issuer, desired.client_id) do
        Hexpm.RepoBase.rollback(:connection_has_identities)
      end

      attrs =
        metadata
        |> Map.merge(%{
          organization_id: organization.id,
          issuer: desired.issuer,
          client_id: desired.client_id,
          client_secret: supplied_secret || connection.client_secret,
          configured_by_user_id: audit_data.user.id,
          version: connection.version + 1,
          tested_at: nil,
          pending_client_secret: nil,
          pending_client_secret_version: nil,
          pending_client_secret_tested_at: nil,
          enabled_at: nil
        })

      changeset = Connection.configuration_changeset(connection, attrs)

      case Repo.insert_or_update(changeset, log: false) do
        {:ok, saved} ->
          insert_audit!(audit_data, "sso.connection.configure", {
            organization,
            %{issuer: saved.issuer, client_id: saved.client_id}
          })

          saved

        {:error, changeset} ->
          Hexpm.RepoBase.rollback(changeset)
      end
    end)
  end

  def refresh_metadata(%Connection{} = connection) do
    with {:ok, metadata} <- OIDC.impl().discover(connection.issuer) do
      Repo.transaction(fn ->
        current = locked_connection!(connection.id)

        # Refreshing metadata deliberately leaves version alone. Transactions
        # pin themselves to it, so bumping here would refuse every login that
        # was already in flight, on every discovery cache expiry. The guard
        # still catches a configure landing while discovery was being fetched,
        # because configure does bump it.
        if current.version == connection.version and current.issuer == connection.issuer do
          current
          |> Connection.configuration_changeset(metadata)
          |> Repo.update!()
        else
          Hexpm.RepoBase.rollback(:connection_configuration_changed)
        end
      end)
    end
  end

  def begin_rotation(organization, client_secret, audit: audit_data) do
    with_existing_connection(
      organization,
      audit_data.user,
      &require_active/1,
      :not_configured,
      fn connection ->
        secret = present(client_secret) || Hexpm.RepoBase.rollback(:not_configured)
        pending_version = (connection.pending_client_secret_version || 0) + 1

        saved =
          connection
          |> Connection.rotation_changeset(%{
            pending_client_secret: secret,
            pending_client_secret_version: pending_version,
            pending_client_secret_tested_at: nil
          })
          |> Repo.update!(log: false)

        insert_audit!(audit_data, "sso.connection.rotation.start", {organization, %{}})
        saved
      end
    )
  end

  def promote_rotation(organization, audit: audit_data) do
    with_existing_connection(
      organization,
      audit_data.user,
      &require_active/1,
      :rotation_not_ready,
      fn connection ->
        with secret when not is_nil(secret) <- connection.pending_client_secret,
             %DateTime{} = tested_at <- connection.pending_client_secret_tested_at do
          saved =
            connection
            |> change(
              client_secret: secret,
              pending_client_secret: nil,
              pending_client_secret_version: nil,
              version: connection.version + 1,
              tested_at: tested_at,
              pending_client_secret_tested_at: nil
            )
            |> Repo.update!(log: false)

          insert_audit!(audit_data, "sso.connection.rotation.complete", {organization, %{}})
          saved
        else
          _other -> Hexpm.RepoBase.rollback(:rotation_not_ready)
        end
      end
    )
  end

  def enable(organization, audit: audit_data) do
    with_existing_connection(
      organization,
      audit_data.user,
      &require_feature/1,
      :connection_not_tested,
      fn connection ->
        if connection.tested_at do
          saved = Repo.update!(change(connection, enabled_at: DateTime.utc_now()))
          insert_audit!(audit_data, "sso.connection.enable", {organization, %{}})
          saved
        else
          Hexpm.RepoBase.rollback(:connection_not_tested)
        end
      end
    )
  end

  def disable(organization, audit: audit_data) do
    with_existing_connection(
      organization,
      audit_data.user,
      &require_active/1,
      :not_configured,
      fn connection ->
        saved = Repo.update!(change(connection, enabled_at: nil, version: connection.version + 1))

        # Disabling is what an administrator reaches for when the provider is
        # compromised, so the access it already granted goes too rather than
        # lasting out its 24 hours.
        now = DateTime.utc_now()

        Repo.update_all(
          from(session in OrgSession,
            where: session.organization_id == ^organization.id,
            where: is_nil(session.revoked_at)
          ),
          set: [revoked_at: now, updated_at: now]
        )

        insert_audit!(audit_data, "sso.connection.disable", {organization, %{}})
        saved
      end
    )
  end

  @doc """
  Removes the connection and everything reaching it: identities, transactions,
  failures, and the organization access sessions the identities own. The
  connection must be disabled first, so the members it covers have already lost
  SSO before their links go.
  """
  def delete_connection(organization, audit: audit_data) do
    with_existing_connection(
      organization,
      audit_data.user,
      &require_active/1,
      :not_configured,
      fn connection ->
        if Connection.enabled?(connection) do
          Hexpm.RepoBase.rollback(:connection_enabled)
        end

        insert_audit!(audit_data, "sso.connection.delete", {organization, %{}})
        Repo.delete!(connection)
      end
    )
  end

  def start_login(organization, user, return_path, redirect_uri, opts \\ []) do
    entrypoint = Keyword.get(opts, :entrypoint, "organization")

    with :ok <- require_entrypoint(entrypoint),
         :ok <- require_active(organization) do
      start_transaction(organization, user, redirect_uri,
        kind: "login",
        secret_slot: "active",
        login_hint: Keyword.get(opts, :login_hint),
        gate: fn connection ->
          with :ok <- require_connection_enabled(connection),
               do: require_member_or_jit(connection, user)
        end,
        locked_gate: fn connection ->
          with :ok <- require_connection_enabled(connection),
               do: require_locked_member_or_jit(connection, user)
        end,
        secret: fn connection -> {:ok, connection.client_secret} end,
        transaction: [
          return_path: return_path,
          entrypoint: entrypoint,
          target_user_session_id: Keyword.get(opts, :target_user_session_id)
        ]
      )
    end
  end

  def start_test(organization, user, secret_slot, redirect_uri) do
    secret_slot = to_string(secret_slot)

    with :ok <- require_active(organization),
         :ok <- require_admin(organization, user) do
      start_transaction(organization, user, redirect_uri,
        kind: "test",
        secret_slot: secret_slot,
        gate: &require_configuration_admin(&1, user, secret_slot),
        locked_gate: fn connection ->
          with :ok <- require_locked_admin(connection.organization, user),
               do: require_configuration_admin(connection, user, secret_slot)
        end,
        secret: &secret_for_slot(&1, secret_slot)
      )
    end
  end

  # Both ways of starting a provider round trip: check the connection is in a
  # state that can serve one, take its lock, check again under it, write the
  # transaction, and hand the provider URI back. They differ only in the gates,
  # the kind of transaction, and which secret signs the request.
  defp start_transaction(organization, user, redirect_uri, opts) do
    kind = Keyword.fetch!(opts, :kind)
    secret_slot = Keyword.fetch!(opts, :secret_slot)
    gate = Keyword.fetch!(opts, :gate)
    locked_gate = Keyword.fetch!(opts, :locked_gate)
    secret = Keyword.fetch!(opts, :secret)
    login_hint = Keyword.get(opts, :login_hint)
    transaction_opts = Keyword.get(opts, :transaction, [])

    with %Connection{} = connection <- get_connection(organization) |> Repo.preload(:organization),
         :ok <- gate.(connection),
         {:ok, connection} <- refresh_metadata_if_expired(connection),
         {:ok, {transaction, uri}} <-
           Repo.transaction(fn ->
             connection = locked_connection!(connection.id)

             with :ok <- require_active(connection.organization),
                  :ok <- locked_gate.(connection),
                  {:ok, client_secret} <- secret.(connection),
                  {:ok, transaction, state} <-
                    create_transaction(
                      connection,
                      user,
                      kind,
                      secret_slot,
                      redirect_uri,
                      transaction_opts
                    ),
                  transaction = %{
                    transaction
                    | raw_state: state,
                      login_hint: login_hint,
                      connection: connection
                  },
                  {:ok, uri} <-
                    OIDC.impl().authorization_uri(
                      connection,
                      transaction,
                      redirect_uri,
                      client_secret
                    ) do
               {transaction, uri}
             else
               {:error, reason} -> Hexpm.RepoBase.rollback(reason)
             end
           end) do
      {:ok, transaction, uri}
    else
      nil ->
        {:error, :not_configured}

      {:error, %Error{} = error} = result ->
        maybe_record_failure(get_connection(organization), error)
        result

      {:error, _reason} = error ->
        error
    end
  end

  def get_transaction_by_state(state) when is_binary(state) and byte_size(state) <= 512 do
    now = DateTime.utc_now()

    from(transaction in SSOTransaction,
      where: transaction.state_hash == ^hash(state),
      where: is_nil(transaction.consumed_at),
      where: transaction.expires_at > ^now,
      preload: [connection: :organization]
    )
    |> Repo.one(log: false)
  end

  def get_transaction_by_state(_state), do: nil

  def exchange_code(%SSOTransaction{} = transaction, code, redirect_uri) do
    connection = transaction.connection

    with :ok <- callback_available?(transaction),
         :ok <- transaction_configuration_available?(transaction, connection),
         true <- redirect_uri == transaction.redirect_uri,
         {:ok, client_secret} <- secret_for_slot(connection, transaction.secret_slot) do
      OIDC.impl().exchange_code(
        connection,
        transaction,
        code,
        transaction.redirect_uri,
        client_secret
      )
    else
      false ->
        {:error, %Error{stage: :callback, code: :redirect_uri_mismatch}}

      # The gates answer with a bare code. Wrapping it is what routes the refusal
      # through abandon/4, so the administrator gets a diagnostic and the
      # authorization code the provider still honours is consumed.
      {:error, code} ->
        {:error, %Error{stage: :callback, code: code}}
    end
  end

  def complete_callback(transaction, claims, current_user, user_session_id, audit_data) do
    result =
      Repo.transaction(fn ->
        connection = locked_connection!(transaction.connection_id)
        transaction = locked_transaction!(transaction.id)

        with :ok <- transaction_available?(transaction),
             :ok <- callback_available?(%{transaction | connection: connection}),
             :ok <- transaction_configuration_available?(transaction, connection),
             :ok <- validate_callback_claims(connection, claims) do
          maybe_update_jwks(connection, claims)

          case transaction.kind do
            "test" ->
              complete_test!(transaction, connection, current_user, audit_data)

            "login" ->
              complete_login!(
                transaction,
                connection,
                claims,
                current_user,
                user_session_id,
                audit_data
              )
          end
        else
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      end)

    case result do
      # A rejection commits: it consumed the transaction and recorded its own
      # failure, so the caller must not record a second one.
      {:ok, {:reject, reason}} ->
        {:error, reason}

      # A rollback left nothing behind, so the diagnostic has to be written here.
      {:error, reason} ->
        record_failure(transaction.connection, :callback, reason)
        {:error, reason}

      result ->
        result
    end
  end

  @doc """
  Turns just-in-time membership on or off.

  Turning it on needs a verified domain, because otherwise the organization
  would be admitting anyone whose provider happens to return any address at all.
  """
  def configure_jit(organization, params, audit: audit_data) do
    update_connection(organization, audit_data,
      changeset: &Connection.jit_changeset(&1, params),
      require: &require_feature/1,
      gate: &require_verified_domain(organization, &1),
      action: "sso.jit.configure",
      audit_params: &%{jit_seat_policy: &1.jit_seat_policy, jit_role: &1.jit_role}
    )
  end

  # Every connection setting is saved the same way: the gate the setting takes
  # against the organization, the row lock and the administrator check under it,
  # then the changeset, the gate that setting takes against it, the save, and
  # the log.
  defp update_connection(organization, audit_data, opts) do
    changeset_fun = Keyword.fetch!(opts, :changeset)
    requirement = Keyword.fetch!(opts, :require)
    gate = Keyword.fetch!(opts, :gate)
    action = Keyword.fetch!(opts, :action)
    audit_params = Keyword.fetch!(opts, :audit_params)
    after_update = Keyword.get(opts, :after_update, fn _connection -> :ok end)

    with_existing_connection(
      organization,
      audit_data.user,
      requirement,
      :not_configured,
      fn connection ->
        changeset = changeset_fun.(connection)

        with :ok <- gate.(changeset) do
          case Repo.update(changeset) do
            {:ok, connection} ->
              :ok = after_update.(connection)
              insert_audit!(audit_data, action, {organization, audit_params.(connection)})
              connection

            {:error, changeset} ->
              Hexpm.RepoBase.rollback(changeset)
          end
        else
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      end
    )
  end

  defp require_verified_domain(organization, changeset) do
    policy = Ecto.Changeset.get_field(changeset, :jit_seat_policy)

    if is_nil(policy) or OrganizationDomains.all_verified(organization) != [] do
      :ok
    else
      {:error, :domain_required}
    end
  end

  @doc """
  Sets the enforcement mode, its start date, the organization access session
  lifetime, and what happens to personal API keys.
  """
  def configure_enforcement(organization, params, audit: audit_data) do
    update_connection(organization, audit_data,
      changeset: &Connection.enforcement_changeset(&1, params),
      require: &require_active/1,
      gate: &require_reachable_admin(organization, &1),
      after_update: &clamp_org_sessions(organization, &1),
      action: "sso.enforcement.configure",
      audit_params:
        &%{
          enforcement_mode: &1.enforcement_mode,
          required_at: &1.required_at,
          session_lifetime_seconds: &1.session_lifetime_seconds,
          personal_keys: &1.personal_keys
        }
    )
  end

  # `expires_at` is stamped at authentication, so an administrator who cuts the
  # lifetime during an incident would otherwise leave every session already open
  # running for the old one. Sessions are only ever shortened: the setting is
  # about how long ago the provider has to have vouched for someone, and
  # extending it would push that further into the past than the organization
  # asked for.
  defp clamp_org_sessions(organization, connection) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, Enforcement.session_lifetime(connection), :second)

    Repo.update_all(
      from(session in OrgSession,
        where: session.organization_id == ^organization.id,
        where: is_nil(session.revoked_at),
        where: session.expires_at > ^cutoff
      ),
      set: [expires_at: cutoff, updated_at: now]
    )

    :ok
  end

  # Required mode with nobody able to administer the organization is a lockout
  # the carve-out cannot undo, so it is refused while the admin can still act.
  defp require_reachable_admin(organization, changeset) do
    if Ecto.Changeset.get_field(changeset, :enforcement_mode) == "required" and
         not reachable_admin?(organization) do
      {:error, :no_reachable_admin}
    else
      :ok
    end
  end

  # An administrator enforcement cannot lock out: exempt from it, or linked and
  # able to authenticate.
  defp reachable_admin?(organization) do
    Repo.exists?(
      from(member in Enforcement.members_with_identity(organization),
        where: member.role == "admin",
        where: member.sso_enforcement == "exempt" or not is_nil(as(:identity).id)
      )
    )
  end

  @doc """
  Sets whether SSO is enforced for one member regardless of the organization's
  mode. Nil follows the mode, "enforced" always does, "exempt" never does.

  The last administrator an organization already requiring SSO can still reach
  it with cannot be enforced away here, the same lockout the mode change is
  refused for. An organization that has no reachable administrator left is not
  held to it, because the change that would give it one goes through here too.
  """
  def set_member_enforcement(organization, user, enforcement, audit: audit_data) do
    # The connection lock serialises this against the mode change and against
    # another member's, so two of them cannot each rely on an administrator the
    # other is taking away.
    with_locked_connection(organization, audit_data.user, &require_active/1, fn connection ->
      reachable_before? =
        Enforcement.mode(organization, connection) == :required and
          reachable_admin?(organization)

      member =
        Repo.get_by(OrganizationUser,
          organization_id: organization.id,
          user_id: user.id
        ) || Hexpm.RepoBase.rollback(:not_member)

      changeset =
        OrganizationUser.enforcement_changeset(member, %{"sso_enforcement" => enforcement})

      case Repo.update(changeset) do
        {:ok, member} ->
          if reachable_before? and not reachable_admin?(organization) do
            Hexpm.RepoBase.rollback(:no_reachable_admin)
          end

          insert_audit!(audit_data, "sso.enforcement.member", {
            organization,
            user,
            member.sso_enforcement
          })

          member

        {:error, changeset} ->
          Hexpm.RepoBase.rollback(changeset)
      end
    end)
  end

  @doc """
  Buys the seat a just-in-time join is about to need, when the organization
  chose to auto-expand.

  Runs before `complete_callback/5` rather than inside it, because a billing
  request cannot sit in a database transaction. Always returns `:ok`: a failed
  expansion is not a reason to refuse a login, it just means the claim inside
  the callback rejects and the person is told the organization is full.
  """
  def maybe_expand_seats(%SSOTransaction{} = transaction, user, claims) do
    connection = Repo.get(Connection, transaction.connection_id) |> Repo.preload(:organization)
    transaction = Repo.get(SSOTransaction, transaction.id, log: false)

    if connection && transaction && expands_seat?(transaction, connection, user, claims) do
      expand_seats(connection)
    end

    :ok
  end

  # The callback this seat is for has to be one the callback can still accept.
  # A transaction that is spent, expired, or belongs to another account is about
  # to be rejected, and the seat would be bought for a login that never happens.
  # The connection is held to the same conditions the locked completion holds it
  # to, so an administrator disabling or reconfiguring it while the provider was
  # answering costs the organization nothing.
  defp expands_seat?(transaction, connection, user, claims) do
    transaction.kind == "login" and transaction.user_id == user.id and
      transaction_available?(transaction) == :ok and
      callback_available?(%{transaction | connection: connection}) == :ok and
      transaction_configuration_available?(transaction, connection) == :ok and
      connection.jit_seat_policy == "expand" and
      jit_admits(connection, claims.email, claims[:email_verified] == true) == :ok and
      is_nil(Organizations.get_role(connection.organization, user))
  end

  defp expand_seats(connection) do
    organization = connection.organization

    # The target is absolute rather than one more than whatever is subscribed
    # now, so two first logins at once compute the same number, one wins the
    # claim, and the other expands again on its next attempt instead of both
    # buying a seat.
    case Repo.transaction(fn ->
           {Seats.claim(organization, unknown: :deny), Seats.used(organization)}
         end) do
      {:ok, {{:error, :seats_exhausted}, used}} ->
        purchase_seat(connection, organization, used + 1)

      _other ->
        :ok
    end
  end

  # A billing call that did not take effect must not be repeated on the next
  # login, or a card that needs confirming turns every retry into another
  # charge attempt. The refusal is recorded like any other, which is also what
  # rate-limits the notice to the administrators.
  defp purchase_seat(connection, organization, quantity) do
    if recent_failure?(connection, "expansion_failed") do
      :ok
    else
      organization
      |> Seats.update_quantity(quantity, fn quantity ->
        Hexpm.Billing.update(organization.name, %{"quantity" => quantity},
          audit: %{audit_data: AuditLogs.system(organization), organization: organization}
        )
      end)
      |> case do
        {:ok, _customer} ->
          :ok

        _other ->
          record_failure(connection, :login, :expansion_failed)
          enqueue_seats_notice!(connection, "expansion_failed")
      end
    end
  end

  @doc """
  Ends a login attempt that cannot be completed and records why.

  Consuming the transaction here is what stops a replay: the authorization code
  is still valid at the provider, and the state is still in the browser.
  """
  def abandon_login(%SSOTransaction{} = transaction, stage, code) do
    Repo.transaction(fn ->
      # Connection before transaction, matching complete_callback. Recording a
      # failure takes a share lock on the connection through its foreign key, so
      # taking the transaction first would invert the order against a concurrent
      # callback and deadlock.
      locked_connection!(transaction.connection_id)
      transaction = locked_transaction!(transaction.id)

      if is_nil(transaction.consumed_at) do
        consume_transaction!(transaction, %{})
      end

      record_failure(transaction.connection, stage, code)
    end)

    :ok
  end

  @doc """
  Adopts a pending subject for the signed-in account and unlocks the
  organization.

  Consent completes an SSO authentication that is seconds old, so it produces an
  organization access session in its own right. Without that the member would
  have to run the whole provider round trip a second time to reach the
  organization they just linked.
  """
  def complete_link(transaction_id, raw_link_token, user, user_session_id, audit_data) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) || Hexpm.RepoBase.rollback(:invalid_link)

      connection = locked_connection!(transaction.connection_id, :invalid_link)
      organization = connection.organization

      with :ok <- require_active(organization),
           :ok <- require_connection_enabled(connection) do
        transaction = locked_transaction!(transaction_id, :invalid_link)

        with :ok <- link_available?(transaction, raw_link_token),
             :ok <- transaction_configuration_available?(transaction, connection),
             true <- transaction.user_id == user.id,
             :ok <- admit_member(connection, transaction, user, audit_data) do
          identity =
            Identity.changeset(%Identity{}, %{
              organization_id: organization.id,
              connection_id: connection.id,
              user_id: user.id,
              issuer: transaction.issuer,
              subject: transaction.subject,
              provider_email: transaction.provider_email
            })

          case Repo.insert(identity, log: false) do
            {:ok, identity} ->
              Repo.update!(
                SSOTransaction.consume_changeset(transaction, %{
                  linked_at: DateTime.utc_now(),
                  link_token_hash: nil,
                  issuer: nil,
                  subject: nil,
                  provider_email: nil,
                  sid: nil
                })
              )

              insert_audit!(%{audit_data | user: user}, "sso.identity.link", {
                organization,
                %{user_id: user.id, entrypoint: transaction.entrypoint}
              })

              org_session =
                establish_login!(
                  transaction,
                  connection,
                  identity,
                  user,
                  user_session_id,
                  transaction.sid,
                  audit_data
                )

              enqueue_sso_notification!("identity_linked", connection, user)
              {identity, org_session}

            {:error, changeset} ->
              Hexpm.RepoBase.rollback({:identity_conflict, changeset})
          end
        else
          false -> Hexpm.RepoBase.rollback(:session_user_mismatch)
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      else
        {:error, reason} -> Hexpm.RepoBase.rollback(reason)
      end
    end)
  end

  def cancel_link(transaction_id, raw_link_token) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) || Hexpm.RepoBase.rollback(:invalid_link)

      transaction = locked_transaction!(transaction.id, :invalid_link)

      with :ok <- link_available?(transaction, raw_link_token) do
        Repo.update!(
          SSOTransaction.consume_changeset(transaction, %{
            cancelled_at: DateTime.utc_now(),
            link_token_hash: nil,
            issuer: nil,
            subject: nil,
            provider_email: nil,
            sid: nil
          })
        )
      else
        {:error, reason} -> Hexpm.RepoBase.rollback(reason)
      end
    end)
  end

  def get_pending_link(transaction_id, raw_link_token) do
    transaction =
      Repo.get(SSOTransaction, transaction_id)
      |> Repo.preload(connection: :organization)

    if transaction && link_available?(transaction, raw_link_token) == :ok do
      transaction
    end
  end

  def unlink_identity(organization, user, audit: audit_data) do
    with_locked_connection(organization, audit_data.user, &require_active/1, fn
      nil ->
        nil

      connection ->
        identity =
          from(identity in Identity,
            where: identity.connection_id == ^connection.id,
            where: identity.user_id == ^user.id,
            lock: "FOR UPDATE"
          )
          |> Repo.one()

        if identity do
          Repo.delete_all(
            from(transaction in SSOTransaction,
              where: transaction.connection_id == ^identity.connection_id,
              where:
                transaction.user_id == ^user.id or
                  (transaction.issuer == ^identity.issuer and
                     transaction.subject == ^identity.subject)
            ),
            log: false
          )

          Repo.delete_all(
            from(session in OrgSession, where: session.identity_id == ^identity.id),
            log: false
          )

          Repo.delete!(identity)

          insert_audit!(audit_data, "sso.identity.unlink", {organization, %{user_id: user.id}})

          delete_notifications!(connection, user)
          enqueue_sso_notification!("identity_unlinked", connection, user)
          identity
        end
    end)
  end

  def delete_member_identities(multi, organization, user) do
    multi
    |> Multi.delete_all(
      :organization_sso_sessions,
      from(session in OrgSession,
        where: session.organization_id == ^organization.id and session.user_id == ^user.id
      )
    )
    |> Multi.delete_all(
      :organization_sso_identities,
      from(identity in Identity,
        where: identity.organization_id == ^organization.id and identity.user_id == ^user.id
      )
    )
  end

  @doc """
  What a removed member takes with them: the transactions they started, their
  identity and the organization access it granted, and the notifications about
  a state that is about to stop being true.

  An organization has one connection or none, so it is read once for all four
  steps rather than once per step.
  """
  def remove_member(multi, organization, user) do
    connection = get_connection(organization, [:organization])

    multi
    |> delete_member_transactions(connection, user)
    |> enqueue_member_unlink_notification(connection, user)
    |> delete_member_identities(organization, user)
    |> delete_member_notifications(connection, user)
  end

  def lock_member_removal(multi, organization, user) do
    Multi.run(multi, :organization_sso_locks, fn _repo, _changes ->
      locked_connection_for_organization(organization)
      locked_member(organization, user)
      {:ok, :locked}
    end)
  end

  defp enqueue_member_unlink_notification(multi, nil, _user), do: multi

  defp enqueue_member_unlink_notification(multi, connection, user) do
    Multi.run(multi, :organization_sso_unlink_notification, fn _repo, _changes ->
      if Repo.get_by(Identity, connection_id: connection.id, user_id: user.id) do
        delete_notifications!(connection, user)
        enqueue_sso_notification!("identity_unlinked", connection, user)
      end

      {:ok, :notified}
    end)
  end

  defp delete_member_transactions(multi, nil, _user), do: multi

  defp delete_member_transactions(multi, connection, user) do
    Multi.delete_all(
      multi,
      :organization_sso_transactions,
      from(transaction in SSOTransaction,
        where: transaction.connection_id == ^connection.id,
        where: transaction.user_id == ^user.id
      )
    )
  end

  defp delete_member_notifications(multi, nil, _user), do: multi

  # Only the categories that describe a state the caller is about to undo. An
  # unlink notification stands whatever else happens.
  defp delete_member_notifications(multi, connection, user) do
    Outbox.cancel(multi, :organization_sso_email_outbox,
      group_key: notification_group_key(connection, user),
      categories: @cancelled_notification_categories
    )
  end

  # The account is going away, so every notification about it goes with it,
  # across every organization it was linked to.
  def delete_user_notifications(multi, user) do
    Outbox.cancel(multi, :organization_sso_email_outbox,
      scope_key: notification_scope_key(user),
      categories: @notification_categories
    )
  end

  def lock_user_removal(multi, user) do
    Multi.run(multi, :organization_sso_user_removal_locks, fn _repo, _changes ->
      organization_ids =
        from(organization_user in OrganizationUser,
          where: organization_user.user_id == ^user.id,
          order_by: [asc: organization_user.organization_id],
          select: organization_user.organization_id
        )
        |> Repo.all(log: false)

      from(connection in Connection,
        where: connection.organization_id in ^organization_ids,
        order_by: [asc: connection.organization_id],
        lock: "FOR UPDATE"
      )
      |> Repo.all(log: false)

      from(organization_user in OrganizationUser,
        where: organization_user.user_id == ^user.id,
        order_by: [asc: organization_user.organization_id],
        lock: "FOR UPDATE"
      )
      |> Repo.all(log: false)

      {:ok, :locked}
    end)
  end

  def delete_user_transactions(multi, user) do
    Multi.delete_all(
      multi,
      :organization_sso_user_transactions,
      from(transaction in SSOTransaction, where: transaction.user_id == ^user.id)
    )
  end

  def identities(%Connection{} = connection) do
    from(identity in Identity,
      where: identity.connection_id == ^connection.id,
      order_by: [asc: identity.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Establishes the organization access session an SSO authentication produces.

  Re-authenticating in the same browser session refreshes the existing row
  rather than adding a second one, which is what the unique index on
  `(user_session_id, organization_id)` enforces.
  """
  def establish_org_session!(%Identity{} = identity, user_session_id, sid \\ nil) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(row in Identity, where: row.id == ^identity.id),
      set: [last_authenticated_at: now, updated_at: now]
    )

    lifetime =
      from(connection in Connection,
        where: connection.organization_id == ^identity.organization_id
      )
      |> Repo.one()
      |> Enforcement.session_lifetime()

    current =
      from(session in OrgSession,
        where: session.user_session_id == ^user_session_id,
        where: session.organization_id == ^identity.organization_id,
        lock: "FOR UPDATE"
      )
      |> Repo.one(log: false)

    (current || %OrgSession{})
    |> OrgSession.changeset(%{
      user_id: identity.user_id,
      organization_id: identity.organization_id,
      user_session_id: user_session_id,
      identity_id: identity.id,
      authenticated_at: now,
      expires_at: DateTime.add(now, lifetime, :second),
      revoked_at: nil,
      sid: sid
    })
    |> Repo.insert_or_update!()
  end

  # The organization access an authentication produces, and the entry that
  # records it. Both paths that authenticate go through here, so a login and a
  # link cannot come to disagree about what an authentication logs.
  defp establish_login!(transaction, connection, identity, user, user_session_id, sid, audit_data) do
    org_session =
      establish_org_session!(identity, authenticated_session(transaction, user_session_id), sid)

    insert_audit!(%{audit_data | user: user}, "sso.login", {
      connection.organization,
      %{
        user_id: user.id,
        entrypoint: transaction.entrypoint,
        expires_at: org_session.expires_at
      }
    })

    org_session
  end

  @doc """
  Gives a session the organization access the session that authorized it is
  currently carrying.

  Approving a device, or consenting to an OAuth client, happens in a browser
  that has already authenticated for these organizations, so this is that same
  authentication reaching the session it just approved rather than a new one.
  It inherits the expiry too: restarting the clock here would let a member who
  authorized a client just before their own session lapsed walk away with twice
  the window the administrator set.

  The copy names the session it came from, so revoking that one takes the copy
  with it. Someone who signs out because their browser session was stolen means
  the access it handed out as well.
  """
  def grant_org_sessions!(from_user_session_id, to_user_session_id, user_id)
      when is_integer(from_user_session_id) and is_integer(to_user_session_id) do
    now = DateTime.utc_now()

    OrgSession.live(from_user_session_id, now)
    |> OrgSession.for_user(user_id)
    |> Repo.all()
    |> Enum.map(fn source ->
      %OrgSession{}
      |> OrgSession.changeset(%{
        user_id: source.user_id,
        organization_id: source.organization_id,
        user_session_id: to_user_session_id,
        granted_from_user_session_id: from_user_session_id,
        identity_id: source.identity_id,
        authenticated_at: source.authenticated_at,
        expires_at: source.expires_at,
        sid: source.sid
      })
      |> Repo.insert!()
    end)
  end

  def grant_org_sessions!(_from_user_session_id, _to_user_session_id, _user_id), do: []

  @doc """
  The organizations a session is currently carrying access for, which is what
  `grant_org_sessions!/3` would hand on.
  """
  def granted_organization_ids(user_session_id, user_id) when is_integer(user_session_id) do
    live =
      user_session_id
      |> OrgSession.live(DateTime.utc_now())
      |> OrgSession.for_user(user_id)

    Repo.all(from(session in live, select: session.organization_id))
  end

  def granted_organization_ids(_user_session_id, _user_id), do: []

  # Which session an authentication lands on. A transaction started from a
  # terminal names the session it is for; everything else means the browser
  # that started it.
  defp authenticated_session(%SSOTransaction{target_user_session_id: nil}, user_session_id),
    do: user_session_id

  defp authenticated_session(%SSOTransaction{target_user_session_id: target}, _user_session_id),
    do: target

  @doc """
  Opens a re-authorization for a session that has lost its organization access.

  The session doing the asking is the one being authorized. Its owner completes
  the provider round trip in a browser, and the organization access session that
  produces is written against the asking session, so a lapsed terminal costs a
  browser visit rather than a new device authorization and a new refresh token.
  """
  @spec request_authorization(User.t(), integer(), term()) ::
          {:ok, Authorization.t()} | {:error, atom()}
  def request_authorization(%User{} = user, user_session_id, organization_names)
      when is_integer(user_session_id) do
    with {:ok, names} <- authorization_names(organization_names),
         {:ok, organizations} <- authorization_organizations(user, names) do
      code = random_token()

      authorization =
        %Authorization{}
        |> Authorization.changeset(%{
          user_id: user.id,
          user_session_id: user_session_id,
          code_hash: hash(code),
          organization_ids: Enum.map(organizations, & &1.id),
          expires_at: DateTime.add(DateTime.utc_now(), @authorization_lifetime_seconds, :second)
        })
        |> Repo.insert!(log: false)

      {:ok, %{authorization | raw_code: code}}
    end
  end

  defp authorization_names(names) when is_list(names) and names != [] do
    names = Enum.uniq(names)

    if length(names) <= @authorization_organization_limit and
         Enum.all?(names, &(is_binary(&1) and &1 != "" and byte_size(&1) <= 100)) do
      {:ok, names}
    else
      {:error, :invalid_organizations}
    end
  end

  defp authorization_names(_names), do: {:error, :invalid_organizations}

  # A client posts the list it last heard about, which can be as old as its
  # access token, so a name that has since been exempted or turned off is
  # dropped rather than taken as a reason to refuse the ones that still stand.
  defp authorization_organizations(user, names) do
    case Enforcement.governed(user, names) do
      [] -> {:error, :not_governed}
      organizations -> {:ok, organizations}
    end
  end

  @doc """
  The open re-authorization this code names, for this account.

  A revoked or expired target session takes its authorization with it: there is
  nothing left to authorize, and saying so is the same answer as a bad code.
  """
  def get_authorization(code, %User{} = user) when is_binary(code) and byte_size(code) <= 512 do
    now = DateTime.utc_now()

    from(authorization in Authorization,
      join: user_session in assoc(authorization, :user_session),
      where: authorization.code_hash == ^hash(code),
      where: authorization.user_id == ^user.id,
      where: authorization.user_id == user_session.user_id,
      where: is_nil(authorization.consumed_at),
      where: authorization.expires_at > ^now,
      where: is_nil(user_session.revoked_at) and user_session.expires_at > ^now,
      preload: [user_session: user_session]
    )
    |> Repo.one(log: false)
  end

  def get_authorization(_code, _user), do: nil

  @doc """
  The organizations a re-authorization covers, and whether the session it is for
  is currently authenticated to each.
  """
  @spec authorization_status(Authorization.t()) :: [{Organization.t(), boolean()}]
  def authorization_status(%Authorization{} = authorization) do
    now = DateTime.utc_now()

    organizations =
      from(organization in Organization,
        where: organization.id in ^authorization.organization_ids,
        order_by: organization.name
      )
      |> Repo.all()

    live =
      authorization.user_session_id
      |> OrgSession.live(now)
      |> OrgSession.for_user(authorization.user_id)

    authenticated =
      from(session in live,
        where: session.organization_id in ^authorization.organization_ids,
        select: session.organization_id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.map(organizations, fn organization ->
      {organization, MapSet.member?(authenticated, organization.id)}
    end)
  end

  @doc """
  Closes a re-authorization once it has nothing left to do, so the verification
  URI cannot be replayed to renew the session again later.
  """
  def consume_authorization!(%Authorization{} = authorization) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(row in Authorization,
        where: row.id == ^authorization.id,
        where: is_nil(row.consumed_at)
      ),
      set: [consumed_at: now, updated_at: now]
    )

    :ok
  end

  @doc """
  The organization access session for a browser session, or nil.
  """
  def current_org_session(user_session_id, organization_id)
      when is_integer(user_session_id) and is_integer(organization_id) do
    now = DateTime.utc_now()

    from(session in OrgSession.live(user_session_id, now),
      where: session.organization_id == ^organization_id,
      # user_id is denormalised onto the session, so assert it agrees with the
      # browser session rather than trusting the copy on the read path.
      where: session.user_id == as(:user_session).user_id
    )
    |> Repo.one()
  end

  def current_org_session(_user_session_id, _organization_id), do: nil

  def revoke_org_sessions_for_user_session(multi, user_session, revoke_at) do
    Multi.update_all(
      multi,
      :organization_sso_sessions,
      revoke_org_sessions_query([user_session.id], revoke_at),
      []
    )
  end

  @doc """
  The organization access sessions written against these sessions, or against
  every session an account owns, set to revoked.

  The caller runs the query, so revoking sessions in bulk takes the organization
  access they carry with them rather than leaving rows that only the read path
  knows are dead.
  """
  def revoke_org_sessions_query(user_session_ids, revoke_at) when is_list(user_session_ids) do
    now = DateTime.utc_now()

    from(session in OrgSession,
      where: session.user_session_id in ^user_session_ids,
      where: is_nil(session.revoked_at),
      update: [set: [revoked_at: ^revoke_at, updated_at: ^now]]
    )
  end

  def revoke_org_sessions_query(%User{} = user, revoke_at) do
    now = DateTime.utc_now()

    from(session in OrgSession,
      where: session.user_id == ^user.id,
      where: is_nil(session.revoked_at),
      update: [set: [revoked_at: ^revoke_at, updated_at: ^now]]
    )
  end

  @doc """
  Handles a back-channel logout token from the organization's provider.

  The provider says a session of theirs ended, by logout or deactivation, so
  the organization access that authentication created is revoked: the sessions
  from that provider session when the token carries a `sid`, everything the
  identity holds when it does not. An unknown subject and a token with nothing
  left to revoke both succeed, because from the provider's side the logout is
  done and there is nothing here for it to retry.
  """
  def backchannel_logout(%Organization{} = organization, logout_token)
      when is_binary(logout_token) do
    case get_connection(organization) do
      nil ->
        {:error, :not_configured}

      connection ->
        case OIDC.impl().validate_logout_token(connection, logout_token) do
          {:ok, claims} ->
            maybe_update_jwks(connection, claims)
            revoke_backchannel_sessions(connection, organization, claims)

          {:error, %Error{} = error} ->
            record_failure(connection, error)
            {:error, error}
        end
    end
  end

  defp revoke_backchannel_sessions(connection, organization, claims) do
    identity =
      from(identity in Identity,
        where: identity.connection_id == ^connection.id,
        where: identity.issuer == ^claims.issuer,
        where: identity.subject == ^claims.subject,
        preload: [:user]
      )
      |> Repo.one(log: false)

    if identity do
      now = DateTime.utc_now()

      query =
        from(session in OrgSession,
          where: session.identity_id == ^identity.id,
          where: is_nil(session.revoked_at),
          update: [set: [revoked_at: ^now, updated_at: ^now]]
        )

      query =
        case claims.sid do
          nil -> query
          sid -> from(session in query, where: session.sid == ^sid)
        end

      {revoked_count, _} = Repo.update_all(query, [])

      insert_audit!(
        %{user: identity.user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil},
        "sso.backchannel_logout",
        {organization,
         %{
           user_id: identity.user_id,
           revoked_count: revoked_count,
           sid_scoped: not is_nil(claims.sid)
         }}
      )
    end

    :ok
  end

  def failures(%Connection{} = connection) do
    from(failure in Failure,
      where: failure.connection_id == ^connection.id,
      order_by: [desc: failure.inserted_at],
      limit: @diagnostic_limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  def record_failure(%Connection{} = connection, %Error{} = error) do
    do_record_failure(connection, error, nil)
  end

  def record_failure(%Connection{} = connection, stage, code, user \\ nil) do
    do_record_failure(connection, %Error{stage: stage, code: code}, user)
  end

  defp do_record_failure(%Connection{} = connection, %Error{} = error, user) do
    code = stable_failure_code(error.code)

    attrs = %{
      connection_id: connection.id,
      stage: Atom.to_string(error.stage),
      code: to_string(code),
      user_id: failure_user_id(code, user)
    }

    with {:ok, failure} <- Repo.insert(Failure.changeset(%Failure{}, attrs)) do
      keep_recent_failures(connection)
      {:ok, failure}
    end
  end

  # Only codes where we already know which account failed attach it; others stay redacted.
  defp failure_user_id(code, user)
       when code in [
              :not_member,
              :identity_conflict,
              :session_user_mismatch,
              :seats_exhausted,
              :seat_limit_unknown,
              :provider_email_unverified
            ],
       do: user && user.id

  defp failure_user_id(_code, _user), do: nil

  defp require_configuration_admin(_connection, _user, "pending"), do: :ok

  defp require_configuration_admin(
         %Connection{configured_by_user_id: user_id},
         %{id: user_id},
         "active"
       )
       when not is_nil(user_id),
       do: :ok

  defp require_configuration_admin(_connection, _user, "active"),
    do: {:error, :configuration_admin_required}

  defp require_configuration_admin(_connection, _user, _secret_slot), do: :ok

  def failure_message(%Failure{code: code}), do: failure_message(code)

  def failure_message(code),
    do: Map.get(failure_messages(), to_string(stable_failure_code(code)), "SSO request failed")

  defp complete_test!(transaction, connection, current_user, audit_data) do
    with :ok <- require_locked_admin(connection.organization, current_user),
         true <- transaction.user_id == current_user.id do
      now = DateTime.utc_now()

      changes =
        case transaction.secret_slot do
          "active" -> [tested_at: now]
          "pending" -> [pending_client_secret_tested_at: now]
        end

      Repo.update!(change(connection, changes))
      consume_transaction!(transaction, %{})

      insert_audit!(%{audit_data | user: current_user}, "sso.connection.test", {
        connection.organization,
        %{secret_slot: transaction.secret_slot}
      })

      :test
    else
      false -> Hexpm.RepoBase.rollback(:test_user_mismatch)
      {:error, reason} -> Hexpm.RepoBase.rollback(reason)
    end
  end

  # The outcomes every login callback resolves to. `current_user` is the account
  # session the flow began from; SSO never establishes one.
  defp complete_login!(
         transaction,
         connection,
         claims,
         current_user,
         user_session_id,
         audit_data
       ) do
    organization = connection.organization

    identity =
      from(identity in Identity,
        where: identity.connection_id == ^connection.id,
        where: identity.issuer == ^claims.issuer,
        where: identity.subject == ^claims.subject,
        lock: "FOR UPDATE",
        preload: [user: :emails]
      )
      |> Repo.one(log: false)

    cond do
      transaction.user_id != current_user.id ->
        record_failure(connection, :login, :session_user_mismatch, current_user)
        consume_transaction!(transaction, %{})
        {:reject, :session_user_mismatch}

      is_nil(identity) ->
        begin_link!(transaction, connection, claims, current_user)

      identity.user_id != current_user.id ->
        record_failure(connection, :login, :session_user_mismatch, current_user)
        consume_transaction!(transaction, %{})
        {:reject, :session_user_mismatch}

      # Membership is gone but the identity is still bound to this account. With
      # JIT on there is no consent left to ask for, so re-admit rather than
      # unlinking and making them start over.
      is_nil(locked_member(organization, identity.user)) and
          jit_admits(connection, claims.email, claims[:email_verified] == true) == :ok ->
        case join_member(connection, organization, identity.user, audit_data) do
          :ok ->
            login!(transaction, connection, identity, claims, user_session_id, audit_data)

          {:error, reason} ->
            maybe_notify_seats_exhausted(connection, reason)
            record_failure(connection, :login, reason, identity.user)
            consume_transaction!(transaction, %{})
            {:reject, reason}
        end

      not is_nil(locked_member(organization, identity.user)) ->
        login!(transaction, connection, identity, claims, user_session_id, audit_data)

      true ->
        Repo.delete_all(from(candidate in Identity, where: candidate.id == ^identity.id))

        # Audited like an administrator unlink, because the effect is the same
        # and sso.md requires the log to keep who was unlinked and when.
        insert_audit!(
          audit_data,
          "sso.identity.unlink",
          {organization, %{user_id: identity.user_id}}
        )

        record_failure(connection, :login, :not_member, identity.user)
        consume_transaction!(transaction, %{})
        {:reject, :not_member}
    end
  end

  defp login!(transaction, connection, identity, claims, user_session_id, audit_data) do
    notify_email_mismatch? = update_identity_email(identity, claims.email)
    consume_transaction!(transaction, %{})

    org_session =
      establish_login!(
        transaction,
        connection,
        identity,
        identity.user,
        user_session_id,
        claims[:sid],
        audit_data
      )

    if notify_email_mismatch? do
      enqueue_sso_notification!("email_mismatch", connection, identity.user, claims.email)
    end

    {:login, identity.user, org_session, transaction.return_path}
  end

  # A subject nobody has claimed. The signed-in account may adopt it if it
  # already holds an identity-free membership, or if just-in-time membership is
  # on and would admit it.
  defp begin_link!(transaction, connection, claims, current_user) do
    conflicting_identity =
      from(identity in Identity,
        where: identity.connection_id == ^connection.id,
        where: identity.user_id == ^current_user.id,
        lock: "FOR UPDATE"
      )
      |> Repo.one(log: false)

    cond do
      conflicting_identity ->
        record_failure(connection, :login, :identity_conflict, current_user)
        consume_transaction!(transaction, %{})
        {:reject, :identity_conflict}

      not is_nil(locked_member(connection.organization, current_user)) ->
        begin_conventional_link!(transaction, claims)

      true ->
        begin_jit_link!(transaction, connection, claims, current_user)
    end
  end

  # The seat is only checked here, not taken. Consent has not been given yet, so
  # a membership created now would outlive an abandoned consent screen. What
  # this buys is not offering a screen that cannot be honoured.
  defp begin_jit_link!(transaction, connection, claims, current_user) do
    case jit_admits(connection, claims.email, claims[:email_verified] == true) do
      :ok ->
        case Seats.claim(connection.organization, unknown: :deny) do
          {:ok, _usage} ->
            begin_conventional_link!(transaction, claims)

          {:error, reason} ->
            reject_jit(transaction, connection, current_user, reason)
        end

      {:error, reason} ->
        reject_jit(transaction, connection, current_user, rejection_code(reason))
    end
  end

  # The person authenticated through the organization's own provider, so
  # telling them their address was not confirmed is useful and gives nothing
  # away. Whether the organization runs just-in-time membership, or which
  # domains it has verified, is its own business: both come back as not a
  # member, which is also the truth.
  defp rejection_code(:provider_email_unverified), do: :provider_email_unverified
  defp rejection_code(_reason), do: :not_member

  defp reject_jit(transaction, connection, current_user, reason) do
    # Before recording, so the failure this attempt is about to write does not
    # count as the recent one that suppresses the notice.
    maybe_notify_seats_exhausted(connection, reason)
    record_failure(connection, :login, reason, current_user)
    consume_transaction!(transaction, %{})
    {:reject, reason}
  end

  # Membership is created here rather than when the consent screen was offered,
  # so abandoning that screen leaves nothing behind. Runs after the link token
  # has been checked, which keeps the lock order connection, transaction,
  # member, organization seat.
  defp admit_member(connection, transaction, user, audit_data) do
    organization = connection.organization

    cond do
      not is_nil(locked_member(organization, user)) ->
        :ok

      jit_admits(connection, transaction.provider_email, true) != :ok ->
        {:error, :not_member}

      true ->
        join_member(connection, organization, user, audit_data)
    end
  end

  defp join_member(connection, organization, user, audit_data) do
    with {:ok, _usage} <- Seats.claim(organization, unknown: :deny) do
      organization_user = %OrganizationUser{organization_id: organization.id, user_id: user.id}

      case Repo.insert(
             Organization.add_member(organization_user, %{"role" => connection.jit_role})
           ) do
        {:ok, _organization_user} ->
          insert_audit!(%{audit_data | user: user}, "organization.member.add", {
            organization,
            user
          })

          :ok

        {:error, _changeset} ->
          {:error, :not_member}
      end
    end
  end

  # Whether this connection would admit the address, ignoring seats.
  #
  # An `email` claim is whatever the provider chose to assert. `email_verified`
  # is the provider saying it checked, and OIDC has it precisely because the
  # address alone is not authoritative. Membership turns on the address here, so
  # an unverified one is not enough. It is checked wherever the ID token is in
  # hand; callers past that point pass `true`, because the transaction they are
  # working from only exists because the check already passed.
  defp jit_admits(connection, provider_email, email_verified?) do
    cond do
      not Connection.jit_enabled?(connection) ->
        {:error, :jit_disabled}

      not email_verified? ->
        {:error, :provider_email_unverified}

      not OrganizationDomains.verified_for_email?(connection.organization, provider_email) ->
        {:error, :domain_not_verified}

      true ->
        :ok
    end
  end

  # A login loop must not mail the administrators on every attempt, so the
  # failures already being recorded double as the rate limit.
  defp maybe_notify_seats_exhausted(connection, reason)
       when reason in [:seats_exhausted, :seat_limit_unknown] do
    enqueue_seats_notice!(connection, "seats_exhausted")
    :ok
  end

  defp maybe_notify_seats_exhausted(_connection, _reason), do: :ok

  defp recent_failure?(connection, code) do
    cutoff = DateTime.add(DateTime.utc_now(), -@seats_notice_seconds, :second)

    Repo.exists?(
      from(failure in Failure,
        where: failure.connection_id == ^connection.id,
        where: failure.code == ^code,
        where: failure.inserted_at > ^cutoff
      )
    )
  end

  # Rate-limited on the outbox rather than on the failure log: failures are a
  # 20-row ring buffer per connection, and with just-in-time membership on
  # anyone signed in can start a login and fill it, which would reset the
  # window at will. Outbox entries are kept for a month and are not evicted.
  defp enqueue_seats_notice!(connection, kind) do
    group_key = "#{@seats_exhausted_category}:#{kind}:#{connection.id}"
    cutoff = DateTime.add(DateTime.utc_now(), -@seats_notice_seconds, :second)

    recent? =
      Repo.exists?(
        from(entry in Hexpm.Emails.OutboxEntry,
          where: entry.group_key == ^group_key,
          where: entry.inserted_at > ^cutoff
        )
      )

    unless recent?, do: send_seats_notice!(connection, kind, group_key)

    :ok
  end

  defp send_seats_notice!(connection, kind, group_key) do
    organization = connection.organization

    case Enforcement.admin_emails(organization) do
      [] ->
        :ok

      recipients ->
        email = Emails.sso_seats(organization.name, kind, recipients)

        Outbox.enqueue!(email,
          category: @seats_exhausted_category,
          group_key: group_key,
          scope_key: "sso:organization:#{organization.id}"
        )
    end
  end

  defp begin_conventional_link!(transaction, claims) do
    link_token = random_token()

    consume_transaction!(transaction, %{
      issuer: claims.issuer,
      subject: claims.subject,
      provider_email: claims.email,
      sid: claims[:sid],
      link_token_hash: hash(link_token)
    })

    {:link, transaction.id, link_token}
  end

  defp create_transaction(connection, user, kind, secret_slot, redirect_uri, opts) do
    state = random_token()

    attrs = %{
      connection_id: connection.id,
      user_id: user && user.id,
      target_user_session_id: Keyword.get(opts, :target_user_session_id),
      state_hash: hash(state),
      nonce: random_token(),
      code_verifier: random_token(),
      kind: kind,
      secret_slot: secret_slot,
      connection_version: connection.version,
      secret_version: secret_version(connection, secret_slot),
      redirect_uri: redirect_uri,
      return_path: allowed_return_path(Keyword.get(opts, :return_path)),
      entrypoint: Keyword.get(opts, :entrypoint),
      expires_at: DateTime.add(DateTime.utc_now(), @transaction_lifetime_seconds, :second)
    }

    case Repo.insert(SSOTransaction.changeset(%SSOTransaction{}, attrs), log: false) do
      {:ok, transaction} -> {:ok, transaction, state}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp require_entrypoint(entrypoint) when entrypoint in ~w(organization third_party cli), do: :ok
  defp require_entrypoint(_entrypoint), do: {:error, :invalid_entrypoint}

  defp locked_transaction!(id, reason \\ :invalid_transaction) do
    from(transaction in SSOTransaction,
      where: transaction.id == ^id,
      lock: "FOR UPDATE",
      preload: [:connection]
    )
    |> Repo.one()
    |> case do
      nil -> Hexpm.RepoBase.rollback(reason)
      transaction -> transaction
    end
  end

  defp locked_connection!(id, reason \\ :not_configured) do
    from(connection in Connection,
      where: connection.id == ^id,
      lock: "FOR UPDATE",
      preload: [:organization]
    )
    |> Repo.one()
    |> case do
      nil -> Hexpm.RepoBase.rollback(reason)
      connection -> connection
    end
  end

  defp locked_connection_for_organization(organization) do
    from(connection in Connection,
      where: connection.organization_id == ^organization.id,
      lock: "FOR UPDATE",
      preload: [:organization]
    )
    |> Repo.one()
  end

  # The preamble every administrative change to a connection runs: the gate the
  # change takes, then the row lock, then the administrator check again under
  # it, because the first answer was read before the lock and a role can change
  # in between. `fun` is handed the locked connection, or nil when there is
  # none.
  defp with_locked_connection(organization, user, gate, fun) do
    with :ok <- gate.(organization),
         :ok <- require_admin(organization, user) do
      Repo.transaction(fn ->
        connection = locked_connection_for_organization(organization)

        if require_locked_admin(organization, user) != :ok do
          Hexpm.RepoBase.rollback(:admin_required)
        end

        fun.(connection)
      end)
    end
  end

  # As `with_locked_connection/4`, for the changes that need a connection to
  # already exist. `missing` is what the change is refused with when there is
  # none.
  defp with_existing_connection(organization, user, gate, missing, fun) do
    with_locked_connection(organization, user, gate, fn
      nil -> Hexpm.RepoBase.rollback(missing)
      connection -> fun.(connection)
    end)
  end

  defp consume_transaction!(transaction, attrs) do
    attrs =
      attrs
      |> Map.put(:consumed_at, DateTime.utc_now())
      |> Map.put(:nonce, nil)
      |> Map.put(:code_verifier, nil)

    Repo.update!(SSOTransaction.consume_changeset(transaction, attrs), log: false)
  end

  defp transaction_available?(transaction) do
    cond do
      transaction.consumed_at ->
        {:error, :transaction_already_used}

      DateTime.compare(transaction.expires_at, DateTime.utc_now()) != :gt ->
        {:error, :transaction_expired}

      true ->
        :ok
    end
  end

  defp callback_available?(%SSOTransaction{connection: connection, kind: kind}) do
    cond do
      not Features.active?(connection.organization) -> {:error, :feature_disabled}
      kind == "login" and not Connection.enabled?(connection) -> {:error, :connection_disabled}
      true -> :ok
    end
  end

  defp transaction_configuration_available?(transaction, connection) do
    cond do
      transaction.connection_version != connection.version ->
        {:error, :connection_configuration_changed}

      transaction.secret_version != secret_version(connection, transaction.secret_slot) ->
        {:error, :connection_credentials_changed}

      true ->
        :ok
    end
  end

  defp validate_callback_claims(connection, claims) do
    cond do
      not is_map(claims) -> {:error, :invalid_claims}
      claims[:issuer] != connection.issuer -> {:error, :issuer_mismatch}
      not OIDC.valid_subject?(claims[:subject]) -> {:error, :subject_invalid}
      not OIDC.valid_provider_email?(claims[:email]) -> {:error, :provider_email_invalid}
      true -> :ok
    end
  end

  defp link_available?(transaction, raw_link_token) do
    cond do
      transaction.kind != "login" ->
        {:error, :invalid_link}

      is_nil(transaction.consumed_at) ->
        {:error, :invalid_link}

      transaction.linked_at ->
        {:error, :link_already_used}

      transaction.cancelled_at ->
        {:error, :link_cancelled}

      DateTime.compare(transaction.expires_at, DateTime.utc_now()) != :gt ->
        {:error, :link_expired}

      not secure_hash_match?(transaction.link_token_hash, raw_link_token) ->
        {:error, :invalid_link}

      true ->
        :ok
    end
  end

  defp secret_for_slot(connection, "active"), do: {:ok, connection.client_secret}

  defp secret_for_slot(%Connection{pending_client_secret: nil}, "pending"),
    do: {:error, :rotation_not_started}

  defp secret_for_slot(connection, "pending"), do: {:ok, connection.pending_client_secret}
  defp secret_for_slot(_connection, _slot), do: {:error, :invalid_secret_slot}

  defp refresh_metadata_if_expired(connection) do
    if DateTime.compare(connection.metadata_expires_at, DateTime.utc_now()) == :gt do
      {:ok, connection}
    else
      refresh_metadata(connection)
    end
  end

  defp maybe_update_jwks(_connection, %{jwks_document: nil}), do: :ok
  defp maybe_update_jwks(_connection, claims) when not is_map_key(claims, :jwks_document), do: :ok

  defp maybe_update_jwks(connection, %{
         jwks_document: jwks_document,
         jwks_expires_at: jwks_expires_at
       }) do
    metadata_expires_at =
      OIDC.metadata_expires_at(connection.discovery_expires_at, jwks_expires_at)

    Repo.update!(
      change(connection,
        jwks_document: jwks_document,
        jwks_expires_at: jwks_expires_at,
        metadata_expires_at: metadata_expires_at
      )
    )

    :ok
  end

  defp update_identity_email(identity, provider_email) do
    user_emails =
      identity.user.emails
      |> Enum.filter(& &1.verified)
      |> Enum.map(&String.downcase(&1.email))

    normalized_provider_email = provider_email && String.downcase(provider_email)

    mismatch? =
      is_binary(normalized_provider_email) and normalized_provider_email not in user_emails and
        provider_email != identity.provider_email

    if provider_email != identity.provider_email do
      Repo.update!(change(identity, provider_email: provider_email), log: false)
    end

    mismatch?
  end

  # Taking the feature up: a first connection, turning login on, and expanding
  # the subscription for just-in-time members. Those cost money, so they take a
  # subscription.
  defp require_feature(organization) do
    if Features.enabled?(organization), do: :ok, else: {:error, :feature_disabled}
  end

  # Authenticating against a connection that already exists, and repairing or
  # removing one. Enforcement follows the connection, so gating these on billing
  # would leave an organization enforcing a provider it can no longer fix and
  # members locked out of their own private packages over a failed card.
  defp require_active(organization) do
    if Features.active?(organization), do: :ok, else: {:error, :feature_disabled}
  end

  defp require_connection_enabled(connection) do
    if Connection.enabled?(connection), do: :ok, else: {:error, :connection_disabled}
  end

  defp require_admin(organization, user) do
    if user && Organizations.get_role(organization, user) == "admin" do
      :ok
    else
      {:error, :admin_required}
    end
  end

  defp require_locked_admin(organization, user) do
    case user && locked_member(organization, user) do
      %OrganizationUser{role: "admin"} -> :ok
      _other -> {:error, :admin_required}
    end
  end

  defp require_member(organization, user) do
    if Organizations.get_role(organization, user), do: :ok, else: {:error, :not_member}
  end

  defp require_locked_member(organization, user) do
    if locked_member(organization, user), do: :ok, else: {:error, :not_member}
  end

  # A login has to be allowed to start before the provider has said anything, so
  # the domain cannot be checked here. Being turned away happens at the callback,
  # once there is an address to check.
  defp require_member_or_jit(connection, user) do
    if Connection.jit_enabled?(connection) do
      :ok
    else
      require_member(connection.organization, user)
    end
  end

  defp require_locked_member_or_jit(connection, user) do
    if Connection.jit_enabled?(connection) do
      :ok
    else
      require_locked_member(connection.organization, user)
    end
  end

  defp locked_member(organization, user) do
    from(organization_user in OrganizationUser,
      where: organization_user.organization_id == ^organization.id,
      where: organization_user.user_id == ^user.id,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp insert_audit!(audit_data, action, params) do
    audit_data
    |> AuditLog.build(action, params)
    |> Repo.insert!()
  end

  defp enqueue_sso_notification!(kind, connection, user, provider_email \\ nil) do
    recipients = Enforcement.user_emails(user)
    enqueue_sso_notification!(kind, connection, user, provider_email, recipients)
  end

  defp enqueue_sso_notification!(_kind, _connection, _user, _provider_email, []), do: :ok

  defp enqueue_sso_notification!(kind, connection, user, provider_email, recipients) do
    case prepare_sso_notification(kind, connection, user, provider_email, recipients) do
      {:ok, attrs} -> Outbox.insert!(attrs)
      :error -> :ok
    end
  end

  # Rendering and envelope validation run inside the transaction that links an
  # identity or removes a member. Letting them raise would roll that back, so a
  # broken notification loses the mail rather than the security action. The
  # audit log is the durable record either way. The insert stays outside the
  # rescue because it writes through that same transaction: once Postgres has
  # aborted it there is no security action left to save, and swallowing the
  # exception would only hide the rollback from the caller.
  defp prepare_sso_notification(kind, connection, user, provider_email, recipients) do
    organization = connection.organization.name

    {category, email} =
      case kind do
        "identity_linked" ->
          {@identity_linked_email_category,
           Emails.sso_identity_linked(organization, user.username, recipients)}

        "identity_unlinked" ->
          {@identity_unlinked_email_category,
           Emails.sso_identity_unlinked(organization, user.username, recipients)}

        "email_mismatch" ->
          {@email_mismatch_category,
           Emails.sso_email_mismatch(organization, user.username, recipients, provider_email)}
      end

    {:ok,
     Outbox.prepare!(email,
       category: category,
       group_key: notification_group_key(connection, user),
       scope_key: notification_scope_key(user),
       expires_at: Outbox.default_expires_at()
     )}
  rescue
    exception ->
      Sentry.capture_exception(exception,
        stacktrace: __STACKTRACE__,
        extra: %{sso_notification: kind, organization_id: connection.organization_id}
      )

      :error
  end

  defp delete_notifications!(connection, user) do
    Outbox.cancel!(
      group_key: notification_group_key(connection, user),
      categories: @cancelled_notification_categories
    )
  end

  defp notification_group_key(connection, user), do: "sso:#{connection.id}:#{user.id}"
  defp notification_scope_key(user), do: "sso:user:#{user.id}"

  defp keep_recent_failures(connection) do
    recent_ids =
      from(failure in Failure,
        where: failure.connection_id == ^connection.id,
        order_by: [desc: failure.inserted_at, desc: failure.id],
        select: failure.id,
        limit: @diagnostic_limit
      )

    from(failure in Failure,
      where: failure.connection_id == ^connection.id,
      where: failure.id not in subquery(recent_ids)
    )
    |> Repo.delete_all()

    :ok
  end

  defp maybe_record_failure(nil, _error), do: :ok
  defp maybe_record_failure(connection, error), do: record_failure(connection, error)

  defp stable_failure_code({:identity_conflict, _changeset}), do: :identity_conflict
  defp stable_failure_code(code) when is_atom(code) or is_binary(code), do: code
  defp stable_failure_code(_code), do: :unknown

  defp identity_key_changed_with_identities?(%Connection{id: nil}, _issuer, _client_id),
    do: false

  defp identity_key_changed_with_identities?(%Connection{} = connection, issuer, client_id) do
    (connection.issuer != issuer or connection.client_id != client_id) and
      Repo.exists?(from(identity in Identity, where: identity.connection_id == ^connection.id))
  end

  defp failure_messages do
    %{
      "authorization_url_failed" => "The identity provider rejected the login request",
      "client_secret_auth_unsupported" =>
        "The provider does not support client secret authentication",
      "connection_disabled" => "The SSO connection is disabled",
      "id_token_invalid" => "The provider returned an invalid identity token",
      "identity_conflict" => "The SSO identity or Hexpm account is already linked",
      "issuer_mismatch" => "The provider issuer did not match the configured issuer",
      "not_member" => "The Hexpm account is not a member of the organization",
      "seats_exhausted" => "The organization has no seats left for a new member",
      "expansion_failed" => "A seat could not be purchased for a new member",
      "provider_email_unverified" =>
        "The provider did not confirm the email address, so no member was added",
      "seat_limit_unknown" =>
        "The organization's seat count could not be read, so no member was added",
      "pkce_s256_unsupported" => "The provider does not support PKCE with S256",
      "token_endpoint_rejected_request" => "The provider rejected the authorization code",
      "token_endpoint_unavailable" => "The provider token endpoint could not be reached",
      "account_session_required" =>
        "The person was signed out of Hexpm before the login finished",
      "session_user_mismatch" =>
        "The provider identity belongs to a different Hexpm account. Unlink it to move it",
      "connection_configuration_changed" =>
        "The connection was reconfigured while the login was in flight",
      "connection_credentials_changed" =>
        "The client secret changed while the login was in flight",
      "transaction_expired" => "The login took longer than ten minutes and expired",
      "transaction_already_used" => "The login was already completed or replayed",
      "redirect_uri_mismatch" => "The callback did not match the configured redirect URI",
      "subject_invalid" => "The provider sent no usable subject claim",
      "provider_email_invalid" => "The provider sent an unusable email claim",
      "issued_at_invalid" => "The provider identity token had no usable issued-at claim",
      "issued_at_in_future" => "The provider clock is ahead of ours by more than a minute",
      "id_token_missing" => "The provider returned no identity token",
      "id_token_invalid_after_jwks_refresh" =>
        "The identity token failed validation even after refreshing the signing keys",
      "invalid_response" => "The provider response could not be read",
      "provider_error" => "The provider returned an error instead of an authorization code",
      "expired" => "The logout token had already expired",
      "required_claim_missing" =>
        "The logout token was missing a required claim, such as the subject",
      "signature_invalid" => "The logout token signature could not be verified",
      "events_invalid" => "The logout token did not carry the back-channel logout event",
      "nonce_present" => "The logout token carried a nonce, which the specification forbids",
      "issued_at_too_old" => "The logout token was issued more than five minutes ago",
      "invalid" => "The logout token could not be validated"
    }
  end

  defp random_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp hash(value), do: :crypto.hash(:sha256, value)

  defp secure_hash_match?(stored_hash, value) when is_binary(stored_hash) and is_binary(value) do
    Plug.Crypto.secure_compare(stored_hash, hash(value))
  end

  defp secure_hash_match?(_stored_hash, _value), do: false

  @doc """
  The path to send the browser back to once it has authenticated, or nil.

  Enforcement turns a member away wherever they asked for the organization, so
  any path on this site is a place to come back to. Anything that could leave
  the site is not one.
  """
  def allowed_return_path(value) when is_binary(value) do
    if same_origin_path?(value), do: value
  end

  def allowed_return_path(_value), do: nil

  @unsafe_characters ["\\", "\r", "\n", "\t"]

  # No scheme, host, userinfo or fragment to leave the origin with, and no
  # backslash or control character a browser or a response header would read
  # differently to us.
  defp same_origin_path?(value) do
    case URI.parse(value) do
      %URI{scheme: nil, host: nil, userinfo: nil, fragment: nil, path: path} ->
        not String.contains?(value, @unsafe_characters) and safe_path?(path)

      _other ->
        false
    end
  end

  # Judged after every layer of escaping is off, so `%2e%2e` is the traversal
  # and `%2f` is the separator it decodes to. A leading `//` is an authority to
  # a browser rather than a path.
  defp safe_path?(path) when is_binary(path) do
    case fully_decode_path(path) do
      decoded_path when is_binary(decoded_path) ->
        String.starts_with?(decoded_path, "/") and
          not String.starts_with?(decoded_path, "//") and
          not String.contains?(decoded_path, @unsafe_characters) and
          not Enum.any?(String.split(decoded_path, "/"), &(&1 in [".", ".."]))

      nil ->
        false
    end
  rescue
    _exception -> false
  end

  defp safe_path?(_path), do: false

  defp fully_decode_path(path, attempts \\ 0)

  defp fully_decode_path(path, attempts) when attempts < 3 do
    case URI.decode(path) do
      ^path -> path
      decoded -> fully_decode_path(decoded, attempts + 1)
    end
  end

  defp fully_decode_path(_path, _attempts), do: nil

  defp secret_version(connection, "active"), do: connection.version
  defp secret_version(connection, "pending"), do: connection.pending_client_secret_version
  defp secret_version(_connection, _slot), do: nil

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))
  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp present(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp present(_value), do: nil

  defp validate_changeset(%Ecto.Changeset{valid?: true} = changeset),
    do: {:ok, Ecto.Changeset.apply_changes(changeset)}

  defp validate_changeset(%Ecto.Changeset{} = changeset), do: {:error, changeset}
end

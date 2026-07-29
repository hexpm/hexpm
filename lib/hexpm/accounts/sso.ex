defmodule Hexpm.Accounts.SSO do
  use Hexpm.Context

  alias Hexpm.Accounts.SSO.{
    Connection,
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
  alias Hexpm.Emails.{Outbox, OutboxEntry, OutboxLock}

  @transaction_lifetime_seconds 10 * 60
  @diagnostic_limit 20
  @identity_linked_email_category "sso.identity_linked"
  @identity_unlinked_email_category "sso.identity_unlinked"
  @email_mismatch_category "sso.email_mismatch"
  @cancelled_notification_categories [
    @identity_linked_email_category,
    @email_mismatch_category
  ]
  @notification_retention_seconds 30 * 24 * 60 * 60

  def available?, do: Features.available?()
  def enabled?(organization), do: Features.enabled?(organization)

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
    Repo.transaction(fn ->
      current = locked_connection_for_organization(organization)
      connection = current || %Connection{organization_id: organization.id, version: 0}

      if require_locked_admin(organization, audit_data.user) != :ok do
        Hexpm.RepoBase.rollback(:admin_required)
      end

      if Connection.enabled?(connection) do
        Hexpm.RepoBase.rollback(:connection_enabled)
      end

      if identity_key_changed_with_identities?(
           connection,
           desired.issuer,
           desired.client_id
         ) do
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
    |> case do
      {:ok, connection} -> {:ok, connection}
      {:error, reason} -> {:error, reason}
    end
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
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user),
         secret when not is_nil(secret) <- present(client_secret) do
      Repo.transaction(fn ->
        case locked_connection_for_organization(organization) do
          %Connection{} = connection ->
            if require_locked_admin(organization, audit_data.user) != :ok do
              Hexpm.RepoBase.rollback(:admin_required)
            end

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

          nil ->
            Hexpm.RepoBase.rollback(:not_configured)
        end
      end)
    else
      nil -> {:error, :not_configured}
      {:error, _reason} = error -> error
    end
  end

  def promote_rotation(organization, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        connection = locked_connection_for_organization(organization)

        with :ok <- require_locked_admin(organization, audit_data.user),
             %Connection{} <- connection,
             secret when not is_nil(secret) <- connection.pending_client_secret,
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
          {:error, :admin_required} -> Hexpm.RepoBase.rollback(:admin_required)
          _other -> Hexpm.RepoBase.rollback(:rotation_not_ready)
        end
      end)
    else
      {:error, _reason} = error -> error
    end
  end

  def enable(organization, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        connection = locked_connection_for_organization(organization)

        if require_locked_admin(organization, audit_data.user) != :ok do
          Hexpm.RepoBase.rollback(:admin_required)
        end

        if connection && connection.tested_at do
          saved = Repo.update!(change(connection, enabled_at: DateTime.utc_now()))
          insert_audit!(audit_data, "sso.connection.enable", {organization, %{}})
          saved
        else
          Hexpm.RepoBase.rollback(:connection_not_tested)
        end
      end)
    else
      {:error, _reason} = error -> error
    end
  end

  def disable(organization, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        case locked_connection_for_organization(organization) do
          %Connection{} = connection ->
            if require_locked_admin(organization, audit_data.user) != :ok do
              Hexpm.RepoBase.rollback(:admin_required)
            end

            saved =
              Repo.update!(change(connection, enabled_at: nil, version: connection.version + 1))

            insert_audit!(audit_data, "sso.connection.disable", {organization, %{}})
            saved

          nil ->
            Hexpm.RepoBase.rollback(:not_configured)
        end
      end)
    else
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Removes the connection and everything reaching it: identities, transactions,
  failures, and the organization access sessions the identities own. The
  connection must be disabled first, so the members it covers have already lost
  SSO before their links go.
  """
  def delete_connection(organization, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        case locked_connection_for_organization(organization) do
          %Connection{} = connection ->
            if require_locked_admin(organization, audit_data.user) != :ok do
              Hexpm.RepoBase.rollback(:admin_required)
            end

            if Connection.enabled?(connection) do
              Hexpm.RepoBase.rollback(:connection_enabled)
            end

            insert_audit!(audit_data, "sso.connection.delete", {organization, %{}})
            Repo.delete!(connection)

          nil ->
            Hexpm.RepoBase.rollback(:not_configured)
        end
      end)
    else
      {:error, _reason} = error -> error
    end
  end

  def start_login(organization, user, return_path, redirect_uri, opts \\ []) do
    entrypoint = Keyword.get(opts, :entrypoint, "organization")
    login_hint = Keyword.get(opts, :login_hint)

    with :ok <- require_entrypoint(entrypoint),
         :ok <- require_feature(organization),
         :ok <- require_member(organization, user),
         %Connection{} = connection <- get_connection(organization),
         true <- Connection.enabled?(connection),
         {:ok, connection} <- refresh_metadata_if_expired(connection),
         {:ok, {transaction, uri}} <-
           Repo.transaction(fn ->
             connection = locked_connection!(connection.id)

             with :ok <- require_feature(connection.organization),
                  :ok <- require_connection_enabled(connection),
                  :ok <- require_locked_member(connection.organization, user),
                  {:ok, transaction, state} <-
                    create_transaction(
                      connection,
                      user,
                      "login",
                      "active",
                      redirect_uri,
                      return_path,
                      entrypoint
                    ),
                  transaction = %{transaction | raw_state: state, login_hint: login_hint},
                  {:ok, uri} <-
                    OIDC.impl().authorization_uri(
                      connection,
                      transaction,
                      redirect_uri,
                      connection.client_secret
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

      false ->
        {:error, :connection_disabled}

      {:error, %Error{} = error} = result ->
        maybe_record_failure(get_connection(organization), error)
        result

      {:error, _reason} = error ->
        error
    end
  end

  def start_test(organization, user, secret_slot, redirect_uri) do
    secret_slot = to_string(secret_slot)

    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, user),
         %Connection{} = connection <- get_connection(organization),
         :ok <- require_configuration_admin(connection, user, secret_slot),
         {:ok, connection} <- refresh_metadata_if_expired(connection),
         {:ok, {transaction, uri}} <-
           Repo.transaction(fn ->
             connection = locked_connection!(connection.id)

             with :ok <- require_feature(connection.organization),
                  :ok <- require_locked_admin(connection.organization, user),
                  :ok <- require_configuration_admin(connection, user, secret_slot),
                  {:ok, client_secret} <- secret_for_slot(connection, secret_slot),
                  {:ok, transaction, state} <-
                    create_transaction(
                      connection,
                      user,
                      "test",
                      secret_slot,
                      redirect_uri,
                      nil,
                      "organization"
                    ),
                  transaction = %{transaction | raw_state: state},
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
      false -> {:error, %Error{stage: :callback, code: :redirect_uri_mismatch}}
      error -> error
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

      connection = locked_connection!(transaction.connection_id)
      organization = connection.organization

      with :ok <- require_feature(organization),
           :ok <- require_connection_enabled(connection),
           :ok <- require_locked_member(organization, user) do
        transaction = locked_transaction!(transaction_id, :invalid_link)

        with :ok <- link_available?(transaction, raw_link_token),
             :ok <- transaction_configuration_available?(transaction, connection),
             true <- transaction.user_id == user.id do
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
                  provider_email: nil
                })
              )

              insert_audit!(%{audit_data | user: user}, "sso.identity.link", {
                organization,
                %{user_id: user.id, entrypoint: transaction.entrypoint}
              })

              org_session = establish_org_session!(identity, user_session_id)

              insert_audit!(%{audit_data | user: user}, "sso.login", {
                organization,
                %{
                  user_id: user.id,
                  entrypoint: transaction.entrypoint,
                  expires_at: org_session.expires_at
                }
              })

              enqueue_sso_notification!("identity_linked", connection, user)
              {identity, org_session}

            {:error, changeset} ->
              Hexpm.RepoBase.rollback({:identity_conflict, changeset})
          end
        else
          false -> Hexpm.RepoBase.rollback(:account_proof_required)
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
            provider_email: nil
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
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        case locked_connection_for_organization(organization) do
          nil ->
            nil

          connection ->
            if require_locked_admin(organization, audit_data.user) != :ok do
              Hexpm.RepoBase.rollback(:admin_required)
            end

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

              insert_audit!(
                audit_data,
                "sso.identity.unlink",
                {organization, %{user_id: user.id}}
              )

              delete_notifications!(connection, user)
              enqueue_sso_notification!("identity_unlinked", connection, user)
              identity
            end
        end
      end)
    end
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

  def enqueue_member_unlink_notification(multi, organization, user) do
    Multi.run(multi, :organization_sso_unlink_notification, fn _repo, _changes ->
      connection = get_connection(organization, [:organization])

      identity =
        connection &&
          Repo.get_by(Identity, connection_id: connection.id, user_id: user.id)

      if identity do
        delete_notifications!(connection, user)
        enqueue_sso_notification!("identity_unlinked", connection, user)
      end

      {:ok, :notified}
    end)
  end

  def lock_member_removal(multi, organization, user) do
    Multi.run(multi, :organization_sso_locks, fn _repo, _changes ->
      locked_connection_for_organization(organization)
      locked_member(organization, user)
      {:ok, :locked}
    end)
  end

  def delete_member_transactions(multi, organization, user) do
    case get_connection(organization) do
      nil ->
        multi

      connection ->
        Multi.delete_all(
          multi,
          :organization_sso_transactions,
          from(transaction in SSOTransaction,
            where: transaction.connection_id == ^connection.id,
            where: transaction.user_id == ^user.id
          )
        )
    end
  end

  def delete_member_notifications(multi, organization, user) do
    case get_connection(organization) do
      nil ->
        multi

      connection ->
        ordering_key = notification_ordering_key(connection, user)

        multi
        |> Multi.run(:organization_sso_email_outbox_lock, fn _repo, _changes ->
          OutboxLock.acquire!(ordering_key)
          {:ok, :locked}
        end)
        |> Multi.delete_all(
          :organization_sso_email_outbox,
          from(entry in OutboxEntry,
            where: entry.ordering_key == ^ordering_key,
            where: entry.category in @cancelled_notification_categories
          )
        )
    end
  end

  def delete_user_notifications(multi, user) do
    Multi.delete_all(
      multi,
      :organization_sso_email_outbox,
      from(entry in OutboxEntry,
        where: entry.scope_key == ^notification_scope_key(user),
        where:
          entry.category in [
            @identity_linked_email_category,
            @identity_unlinked_email_category,
            @email_mismatch_category
          ]
      )
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
  def establish_org_session!(%Identity{} = identity, user_session_id) do
    now = DateTime.utc_now()

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
      expires_at: DateTime.add(now, OrgSession.lifetime_seconds(), :second),
      revoked_at: nil
    })
    |> Repo.insert_or_update!()
  end

  @doc """
  The organization access session for a browser session, or nil.

  The account session is checked alongside it so that revoking or expiring a
  browser session takes its organization access with it, whichever path did
  the revoking.
  """
  def current_org_session(user_session_id, organization_id)
      when is_integer(user_session_id) and is_integer(organization_id) do
    now = DateTime.utc_now()

    from(session in OrgSession,
      join: user_session in assoc(session, :user_session),
      where: session.user_session_id == ^user_session_id,
      where: session.organization_id == ^organization_id,
      # user_id is denormalised onto the session, so assert it agrees with the
      # browser session rather than trusting the copy on the read path.
      where: session.user_id == user_session.user_id,
      where: is_nil(session.revoked_at) and session.expires_at > ^now,
      where: is_nil(user_session.revoked_at) and user_session.expires_at > ^now
    )
    |> Repo.one()
  end

  def current_org_session(_user_session_id, _organization_id), do: nil

  def revoke_org_sessions_for_user_session(multi, user_session, revoke_at) do
    now = DateTime.utc_now()

    Multi.update_all(
      multi,
      :organization_sso_sessions,
      from(session in OrgSession,
        where: session.user_session_id == ^user_session.id,
        where: is_nil(session.revoked_at)
      ),
      set: [revoked_at: revoke_at, updated_at: now]
    )
  end

  def org_sessions_for_identities(identity_ids) when is_list(identity_ids) do
    now = DateTime.utc_now()

    from(session in OrgSession,
      join: user_session in assoc(session, :user_session),
      where: session.identity_id in ^identity_ids,
      where: is_nil(session.revoked_at) and session.expires_at > ^now,
      where: is_nil(user_session.revoked_at) and user_session.expires_at > ^now,
      order_by: [desc: session.authenticated_at]
    )
    |> Repo.all()
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
    do_record_failure(connection, %Error{stage: stage, code: stable_failure_code(code)}, user)
  end

  defp do_record_failure(%Connection{} = connection, %Error{} = error, user) do
    code = stable_failure_code(error.code)

    attrs = %{
      connection_id: connection.id,
      stage: to_string(stable_failure_code(error.stage)),
      code: to_string(code),
      details: redact_details(error.details),
      user_id: failure_user_id(code, user)
    }

    with {:ok, failure} <- Repo.insert(Failure.changeset(%Failure{}, attrs)) do
      keep_recent_failures(connection)
      {:ok, failure}
    end
  end

  # Only post-proof codes attach the failing user (known there and admin-actionable); others stay redacted.
  defp failure_user_id(code, user)
       when code in [:not_member, :identity_conflict, :session_user_mismatch],
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

  # The four outcomes every login callback resolves to. `current_user` is the
  # account session the flow began from; SSO never establishes one.
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

      not is_nil(locked_member(organization, identity.user)) ->
        notify_email_mismatch? = update_identity_email(identity, claims.email)
        consume_transaction!(transaction, %{})
        org_session = establish_org_session!(identity, user_session_id)

        insert_audit!(%{audit_data | user: identity.user}, "sso.login", {
          organization,
          %{
            user_id: identity.user.id,
            entrypoint: transaction.entrypoint,
            expires_at: org_session.expires_at
          }
        })

        if notify_email_mismatch? do
          enqueue_sso_notification!("email_mismatch", connection, identity.user, claims.email)
        end

        {:login, identity.user, org_session, transaction.return_path}

      true ->
        Repo.delete_all(from(candidate in Identity, where: candidate.id == ^identity.id))
        record_failure(connection, :login, :not_member, identity.user)
        consume_transaction!(transaction, %{})
        {:reject, :not_member}
    end
  end

  # A subject nobody has claimed. The signed-in account may adopt it, but only
  # if it already holds an identity-free membership of this organization.
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

      is_nil(locked_member(connection.organization, current_user)) ->
        record_failure(connection, :login, :not_member, current_user)
        consume_transaction!(transaction, %{})
        {:reject, :not_member}

      true ->
        begin_conventional_link!(transaction, claims)
    end
  end

  defp begin_conventional_link!(transaction, claims) do
    link_token = random_token()

    consume_transaction!(transaction, %{
      issuer: claims.issuer,
      subject: claims.subject,
      provider_email: claims.email,
      link_token_hash: hash(link_token)
    })

    {:link, transaction.id, link_token, transaction.return_path}
  end

  defp create_transaction(
         connection,
         user,
         kind,
         secret_slot,
         redirect_uri,
         return_path,
         entrypoint
       ) do
    state = random_token()

    attrs = %{
      connection_id: connection.id,
      user_id: user && user.id,
      state_hash: hash(state),
      nonce: random_token(),
      code_verifier: random_token(),
      kind: kind,
      secret_slot: secret_slot,
      connection_version: connection.version,
      secret_version: secret_version(connection, secret_slot),
      redirect_uri: redirect_uri,
      return_path: allowed_return_path(connection.organization, return_path),
      entrypoint: entrypoint,
      expires_at: DateTime.add(DateTime.utc_now(), @transaction_lifetime_seconds, :second)
    }

    case Repo.insert(SSOTransaction.changeset(%SSOTransaction{}, attrs), log: false) do
      {:ok, transaction} -> {:ok, transaction, state}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp require_entrypoint(entrypoint) when entrypoint in ~w(organization third_party), do: :ok
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

  defp locked_connection!(id) do
    from(connection in Connection,
      where: connection.id == ^id,
      lock: "FOR UPDATE",
      preload: [:organization]
    )
    |> Repo.one!()
  end

  defp locked_connection_for_organization(organization) do
    from(connection in Connection,
      where: connection.organization_id == ^organization.id,
      lock: "FOR UPDATE",
      preload: [:organization]
    )
    |> Repo.one()
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
      not Features.enabled?(connection.organization) -> {:error, :feature_disabled}
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
      not valid_subject?(claims[:subject]) -> {:error, :subject_invalid}
      not valid_provider_email?(claims[:email]) -> {:error, :provider_email_invalid}
      true -> :ok
    end
  end

  defp valid_subject?(subject) when is_binary(subject) do
    subject != "" and byte_size(subject) <= 255 and
      subject |> :binary.bin_to_list() |> Enum.all?(&(&1 <= 127))
  end

  defp valid_subject?(_subject), do: false

  defp valid_provider_email?(nil), do: true

  defp valid_provider_email?(email) when is_binary(email) do
    byte_size(email) <= 320 and String.valid?(email)
  end

  defp valid_provider_email?(_email), do: false

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
    metadata_expires_at = earliest(connection.discovery_expires_at, jwks_expires_at)

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

  defp require_feature(organization) do
    if Features.enabled?(organization), do: :ok, else: {:error, :feature_disabled}
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
    # The verified primary address only. Any address can be attached to an
    # account unverified, so sending to all of them would let an account holder
    # mail an address they do not own.
    recipients =
      Repo.all(
        from(email in assoc(user, :emails),
          where: email.primary and email.verified,
          select: email.email
        )
      )

    enqueue_sso_notification!(kind, connection, user, provider_email, recipients)
  end

  defp enqueue_sso_notification!(_kind, _connection, _user, _provider_email, []), do: :ok

  defp enqueue_sso_notification!(kind, connection, user, provider_email, recipients) do
    {category, email} =
      case kind do
        "identity_linked" ->
          {@identity_linked_email_category,
           Emails.sso_identity_linked(connection.organization.name, user.username, recipients)}

        "identity_unlinked" ->
          {@identity_unlinked_email_category,
           Emails.sso_identity_unlinked(connection.organization.name, user.username, recipients)}

        "email_mismatch" ->
          {@email_mismatch_category,
           Emails.sso_email_mismatch(
             connection.organization.name,
             user.username,
             recipients,
             provider_email
           )}
      end

    Outbox.enqueue!(email,
      category: category,
      ordering_key: notification_ordering_key(connection, user),
      scope_key: notification_scope_key(user),
      expires_at: DateTime.add(DateTime.utc_now(), @notification_retention_seconds, :second)
    )
  end

  defp delete_notifications!(connection, user) do
    ordering_key = notification_ordering_key(connection, user)
    OutboxLock.acquire!(ordering_key)

    Repo.delete_all(
      from(entry in OutboxEntry,
        where: entry.ordering_key == ^ordering_key,
        where: entry.category in @cancelled_notification_categories
      )
    )
  end

  defp notification_ordering_key(connection, user), do: "sso:#{connection.id}:#{user.id}"
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

  defp redact_details(_details), do: %{}

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
      "pkce_s256_unsupported" => "The provider does not support PKCE with S256",
      "token_endpoint_rejected_request" => "The provider rejected the authorization code",
      "token_endpoint_unavailable" => "The provider token endpoint could not be reached"
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

  def allowed_return_path(organization, value) when is_binary(value) do
    uri = URI.parse(value)
    organization_path = "/dashboard/orgs/#{organization.name}"

    if is_nil(uri.scheme) and is_nil(uri.host) and is_nil(uri.userinfo) and is_nil(uri.fragment) and
         allowed_organization_path?(uri.path, organization_path) do
      value
    end
  end

  def allowed_return_path(_organization, _value), do: nil

  defp allowed_organization_path?(path, organization_path) when is_binary(path) do
    case fully_decode_path(path) do
      decoded_path when is_binary(decoded_path) ->
        segments = String.split(decoded_path, "/")

        not String.contains?(decoded_path, ["\\", "\r", "\n", "\t"]) and
          not Enum.any?(segments, &(&1 in [".", ".."])) and
          (decoded_path == organization_path or
             String.starts_with?(decoded_path, organization_path <> "/"))

      nil ->
        false
    end
  rescue
    _exception -> false
  end

  defp allowed_organization_path?(_path, _organization_path), do: false

  defp fully_decode_path(path, attempts \\ 0)

  defp fully_decode_path(path, attempts) when attempts < 3 do
    case URI.decode(path) do
      ^path -> path
      decoded -> fully_decode_path(decoded, attempts + 1)
    end
  end

  defp fully_decode_path(_path, _attempts), do: nil

  defp earliest(left, right) do
    if DateTime.compare(left, right) == :gt, do: right, else: left
  end

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

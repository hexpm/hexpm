defmodule Hexpm.Accounts.SSO do
  use Hexpm.Context

  alias Hexpm.Accounts.SSO.{
    Connection,
    DomainName,
    DomainVerification,
    Error,
    Failure,
    Features,
    Identity,
    OIDC
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
  @confirmation_code_category "sso.confirmation_code"
  @confirmation_lifetime_seconds 10 * 60
  @verified_confirmation_lifetime_seconds 15 * 60
  @confirmation_max_attempts 5
  @confirmation_max_sends 3
  @confirmation_prune_limit 5
  @cancelled_notification_categories [
    @identity_linked_email_category,
    @email_mismatch_category
  ]
  @notification_retention_seconds 30 * 24 * 60 * 60

  def available?, do: Features.available?()
  def enabled?(organization), do: Features.enabled?(organization)

  def throttle_hash(value) when is_binary(value) do
    :crypto.mac(:hmac, :sha256, Application.fetch_env!(:hexpm, :secret), "sso-throttle:" <> value)
  end

  def get_connection(organization, preload \\ []) do
    Repo.get_by(Connection, organization_id: organization.id)
    |> Repo.preload(preload)
  end

  defdelegate domains(organization), to: DomainVerification, as: :list
  defdelegate add_domain(organization, value, opts), to: DomainVerification, as: :add
  defdelegate verify_domain(organization, id, opts), to: DomainVerification, as: :verify
  defdelegate rotate_domain(organization, id, opts), to: DomainVerification, as: :rotate

  defdelegate update_domain_policy(organization, id, attrs, opts),
    to: DomainVerification,
    as: :update_policy

  defdelegate delete_domain(organization, id, opts), to: DomainVerification, as: :delete
  defdelegate canonical_domain(value), to: DomainName, as: :canonicalize
  defdelegate discovery_domain(value), to: DomainName, as: :from_email
  defdelegate discover_organizations(domain_name), to: DomainVerification, as: :discover

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
          cancel_connection_confirmations!(saved)

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

        if current.version == connection.version and current.issuer == connection.issuer do
          saved =
            current
            |> Connection.configuration_changeset(
              Map.put(metadata, :version, current.version + 1)
            )
            |> Repo.update!()

          cancel_connection_confirmations!(saved)
          saved
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

          cancel_connection_confirmations!(saved)
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

            cancel_connection_confirmations!(saved)
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

  def start_login(organization, return_path, redirect_uri) do
    start_login(organization, return_path, redirect_uri, [])
  end

  def start_login(organization, return_path, redirect_uri, opts) do
    entrypoint = Keyword.get(opts, :entrypoint, "organization")
    domain_name = Keyword.get(opts, :domain)
    login_hint = Keyword.get(opts, :login_hint)

    with :ok <- require_entrypoint(organization, entrypoint, domain_name),
         :ok <- require_feature(organization),
         %Connection{} = connection <- get_connection(organization),
         true <- Connection.enabled?(connection),
         {:ok, connection} <- refresh_metadata_if_expired(connection),
         {:ok, {transaction, uri}} <-
           Repo.transaction(fn ->
             connection = locked_connection!(connection.id)

             with :ok <- require_feature(connection.organization),
                  :ok <- require_connection_enabled(connection),
                  :ok <-
                    require_locked_entrypoint(connection.organization, entrypoint, domain_name),
                  {:ok, transaction, state} <-
                    create_transaction(
                      connection,
                      nil,
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

  def complete_callback(transaction, claims, current_user, audit_data, opts \\ []) do
    allow_automatic_linking = Keyword.get(opts, :automatic_linking, fn -> true end)

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
                audit_data,
                allow_automatic_linking
              )
          end
        else
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      end)

    case result do
      {:ok, {:reject, reason}} -> {:error, reason}
      result -> result
    end
  end

  def complete_link(transaction_id, raw_link_token, user, audit_data) do
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
              provider_email: transaction.provider_email,
              link_method: transaction.link_method || "conventional"
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
                %{
                  user_id: user.id,
                  entrypoint: transaction.entrypoint,
                  link_method: transaction.link_method || "conventional"
                }
              })

              enqueue_sso_notification!("identity_linked", connection, user)
              identity

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

  def prove_link(transaction_id, raw_link_token, user) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) || Hexpm.RepoBase.rollback(:invalid_link)

      connection = locked_connection!(transaction.connection_id)

      with :ok <- require_feature(connection.organization),
           :ok <- require_connection_enabled(connection),
           :ok <- require_locked_member(connection.organization, user) do
        transaction = locked_transaction!(transaction_id, :invalid_link)

        with :ok <- link_available?(transaction, raw_link_token),
             :ok <- transaction_configuration_available?(transaction, connection) do
          Repo.update!(SSOTransaction.consume_changeset(transaction, %{user_id: user.id}))
        else
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

  def get_pending_login(transaction_id, browser_capability) do
    transaction =
      Repo.get(SSOTransaction, transaction_id)
      |> Repo.preload(connection: :organization)

    cond do
      is_nil(transaction) ->
        nil

      pending_login_capability_available?(transaction, browser_capability) != :ok ->
        nil

      pending_login_expired?(transaction) ->
        cancel_pending_login(transaction.id, browser_capability)
        nil

      not Features.enabled?(transaction.connection.organization) ->
        cancel_pending_login(transaction.id, browser_capability)
        nil

      true ->
        transaction
    end
  end

  def complete_pending_login(
        transaction_id,
        browser_capability,
        current_user,
        audit_data
      ) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) ||
          Hexpm.RepoBase.rollback(:invalid_pending_login)

      connection = locked_connection!(transaction.connection_id)
      transaction = locked_transaction!(transaction.id, :invalid_pending_login)

      with :ok <-
             pending_login_capability_available?(transaction, browser_capability) do
        cond do
          pending_login_expired?(transaction) ->
            clear_pending_login!(transaction, cancelled?: true)
            {:error, :pending_login_expired}

          true ->
            case pending_login_context(transaction, connection, current_user) do
              {:ok, identity} ->
                notify_email_mismatch? =
                  update_identity_email(identity, transaction.provider_email)

                clear_pending_login!(transaction)

                insert_audit!(%{audit_data | user: identity.user}, "sso.login", {
                  connection.organization,
                  %{user_id: identity.user.id, entrypoint: transaction.entrypoint}
                })

                if notify_email_mismatch? do
                  enqueue_sso_notification!(
                    "email_mismatch",
                    connection,
                    identity.user,
                    transaction.provider_email
                  )
                end

                {:login, identity.user, connection.organization, transaction.return_path}

              {:error, reason} ->
                clear_pending_login!(transaction, cancelled?: true)
                {:error, reason}
            end
        end
      else
        {:error, reason} -> Hexpm.RepoBase.rollback(reason)
      end
    end)
    |> unwrap_confirmation_result()
  end

  def cancel_pending_login(transaction_id, browser_capability) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) ||
          Hexpm.RepoBase.rollback(:invalid_pending_login)

      transaction = locked_transaction!(transaction.id, :invalid_pending_login)

      with :ok <-
             pending_login_capability_available?(transaction, browser_capability) do
        clear_pending_login!(transaction, cancelled?: true)
        :cancelled
      else
        {:error, reason} -> Hexpm.RepoBase.rollback(reason)
      end
    end)
  end

  def get_pending_confirmation(transaction_id, browser_capability) do
    transaction =
      Repo.get(SSOTransaction, transaction_id)
      |> Repo.preload([
        :candidate_user,
        :candidate_email,
        :domain,
        connection: :organization
      ])

    cond do
      is_nil(transaction) ->
        nil

      not Features.enabled?(transaction.connection.organization) and
          confirmation_capability_available?(transaction, browser_capability) == :ok ->
        cancel_confirmation(transaction.id, browser_capability)
        nil

      not pending_confirmation_context_current?(transaction) and
          confirmation_capability_available?(transaction, browser_capability) == :ok ->
        cancel_confirmation(transaction.id, browser_capability)
        nil

      verified_confirmation_available?(transaction, browser_capability) == :ok ->
        transaction

      confirmation_available?(transaction, browser_capability) == :ok ->
        transaction

      confirmation_expired?(transaction) ->
        expire_confirmation(transaction.id)
        nil

      true ->
        nil
    end
  end

  def confirm_link_code(
        transaction_id,
        browser_capability,
        code,
        current_user,
        audit_data
      ) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) ||
          Hexpm.RepoBase.rollback(:invalid_confirmation)

      connection = locked_connection!(transaction.connection_id)
      transaction = locked_transaction!(transaction.id, :invalid_confirmation)

      with :ok <- confirmation_available?(transaction, browser_capability) do
        attempts = transaction.confirmation_attempts + 1
        code = normalize_confirmation_code(code)

        if secure_confirmation_match?(transaction.confirmation_code_hash, code) do
          case confirmed_link_context(transaction, connection, current_user) do
            {:ok, email, _domain} ->
              if User.tfa_enabled?(email.user) do
                verified_transaction = mark_confirmation_verified!(transaction)

                {:tfa_required, email.user, connection.organization, transaction.return_path,
                 verified_transaction.confirmation_verified_at}
              else
                insert_confirmed_identity!(transaction, connection, email, audit_data)
              end

            {:error, reason} ->
              clear_confirmation!(transaction, cancelled?: true)
              {:error, reason}
          end
        else
          if attempts >= @confirmation_max_attempts do
            clear_confirmation!(transaction, cancelled?: true)
            {:error, :confirmation_attempts_exhausted}
          else
            Repo.update!(
              SSOTransaction.consume_changeset(transaction, %{
                confirmation_attempts: attempts
              }),
              log: false
            )

            {:error, :confirmation_code_invalid}
          end
        end
      else
        {:error, reason} -> Hexpm.RepoBase.rollback(reason)
      end
    end)
    |> unwrap_confirmation_result()
  end

  def complete_confirmed_link_after_tfa(
        transaction_id,
        browser_capability,
        user,
        audit_data
      ) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) ||
          Hexpm.RepoBase.rollback(:invalid_confirmation)

      connection = locked_connection!(transaction.connection_id)
      transaction = locked_transaction!(transaction.id, :invalid_confirmation)

      with :ok <- verified_confirmation_available?(transaction, browser_capability),
           true <- User.tfa_enabled?(user),
           {:ok, email, _domain} <- confirmed_link_context(transaction, connection, user) do
        insert_confirmed_identity!(transaction, connection, email, audit_data)
      else
        false ->
          clear_confirmation!(transaction, cancelled?: true)
          {:error, :tfa_required}

        {:error, reason} ->
          if reason not in [
               :invalid_confirmation,
               :confirmation_already_used,
               :confirmation_cancelled
             ] do
            clear_confirmation!(transaction, cancelled?: true)
          end

          {:error, reason}
      end
    end)
    |> unwrap_confirmation_result()
  end

  def resend_confirmation(transaction_id, browser_capability, current_user) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) ||
          Hexpm.RepoBase.rollback(:invalid_confirmation)

      connection = locked_connection!(transaction.connection_id)
      transaction = locked_transaction!(transaction.id, :invalid_confirmation)

      with :ok <- confirmation_available?(transaction, browser_capability),
           true <- transaction.confirmation_sends < @confirmation_max_sends,
           {:ok, email, _domain} <-
             confirmed_link_context(transaction, connection, current_user) do
        code = confirmation_code()
        expires_at = DateTime.add(DateTime.utc_now(), @confirmation_lifetime_seconds, :second)
        delete_confirmation_email!(transaction)

        Repo.update!(
          SSOTransaction.consume_changeset(transaction, %{
            confirmation_code_hash: confirmation_hash(code),
            confirmation_expires_at: expires_at,
            confirmation_sends: transaction.confirmation_sends + 1
          }),
          log: false
        )

        enqueue_confirmation_code!(transaction, connection, email, code, expires_at)
        :sent
      else
        false ->
          {:error, :confirmation_sends_exhausted}

        {:error, reason} ->
          if reason not in [
               :invalid_confirmation,
               :confirmation_already_used,
               :confirmation_cancelled
             ] do
            clear_confirmation!(transaction, cancelled?: true)
          end

          {:error, reason}
      end
    end)
    |> unwrap_confirmation_result()
  end

  def cancel_confirmation(transaction_id, browser_capability) do
    Repo.transaction(fn ->
      transaction =
        Repo.get(SSOTransaction, transaction_id) ||
          Hexpm.RepoBase.rollback(:invalid_confirmation)

      transaction = locked_transaction!(transaction.id, :invalid_confirmation)

      with :ok <- confirmation_capability_available?(transaction, browser_capability) do
        clear_confirmation!(transaction, cancelled?: true)
        :cancelled
      else
        {:error, reason} -> Hexpm.RepoBase.rollback(reason)
      end
    end)
  end

  def expire_confirmations(opts \\ []) do
    limit =
      opts |> Keyword.get(:limit, @confirmation_prune_limit) |> min(@confirmation_prune_limit)

    now = DateTime.utc_now()

    due_query =
      from(transaction in SSOTransaction,
        where: transaction.link_method == "confirmed_primary_email",
        where: is_nil(transaction.linked_at),
        where: is_nil(transaction.cancelled_at),
        where:
          not is_nil(transaction.confirmation_expires_at) and
            transaction.confirmation_expires_at <= ^now,
        select: transaction.id
      )

    due_count = Repo.aggregate(due_query, :count)

    ids =
      from(transaction in due_query,
        order_by: [asc: transaction.confirmation_expires_at, asc: transaction.id],
        limit: ^limit
      )
      |> Repo.all(log: false)

    Enum.each(ids, &expire_confirmation/1)

    :telemetry.execute(
      [:hexpm, :sso, :confirmation_pruning, :batch],
      %{
        due_count: due_count,
        selected_count: length(ids),
        remaining_count: max(due_count - length(ids), 0)
      },
      %{limit: limit}
    )

    length(ids)
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
    Multi.delete_all(
      multi,
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
            where: transaction.user_id == ^user.id or transaction.candidate_user_id == ^user.id
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
        confirmation_scope_key = confirmation_scope_key(connection, user)

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
        |> Multi.run(:organization_sso_confirmation_outbox_locks, fn _repo, _changes ->
          lock_confirmation_outbox!(
            from(entry in OutboxEntry,
              where: entry.scope_key == ^confirmation_scope_key,
              where: entry.category == @confirmation_code_category
            )
          )

          {:ok, :locked}
        end)
        |> Multi.delete_all(
          :organization_sso_confirmation_email_outbox,
          from(entry in OutboxEntry,
            where: entry.scope_key == ^confirmation_scope_key,
            where: entry.category == @confirmation_code_category
          )
        )
    end
  end

  def delete_user_notifications(multi, user) do
    confirmation_scope_prefix = "sso-confirmation:user:#{user.id}:"

    Multi.delete_all(
      multi,
      :organization_sso_email_outbox,
      from(entry in OutboxEntry,
        where:
          (entry.scope_key == ^notification_scope_key(user) and
             entry.category in [
               @identity_linked_email_category,
               @identity_unlinked_email_category,
               @email_mismatch_category
             ]) or
            (entry.category == @confirmation_code_category and
               like(entry.scope_key, ^"#{confirmation_scope_prefix}%"))
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
      from(transaction in SSOTransaction,
        where: transaction.user_id == ^user.id or transaction.candidate_user_id == ^user.id
      )
    )
  end

  def lock_user_confirmation_notifications(multi, user) do
    confirmation_scope_prefix = "sso-confirmation:user:#{user.id}:"

    Multi.run(multi, :organization_sso_user_confirmation_outbox_locks, fn _repo, _changes ->
      lock_confirmation_outbox!(
        from(entry in OutboxEntry,
          where: entry.category == @confirmation_code_category,
          where: like(entry.scope_key, ^"#{confirmation_scope_prefix}%")
        )
      )

      {:ok, :locked}
    end)
  end

  def pending_domain_confirmation_ids(domain_id) when is_integer(domain_id) do
    from(transaction in SSOTransaction,
      where: transaction.domain_id == ^domain_id,
      where: transaction.link_method == "confirmed_primary_email",
      where: is_nil(transaction.linked_at),
      where: is_nil(transaction.cancelled_at),
      order_by: [asc: transaction.id],
      select: transaction.id
    )
    |> Repo.all(log: false)
  end

  def pending_connection_confirmation_ids(connection_id) when is_integer(connection_id) do
    from(transaction in SSOTransaction,
      where: transaction.connection_id == ^connection_id,
      where: transaction.link_method == "confirmed_primary_email",
      where: is_nil(transaction.linked_at),
      where: is_nil(transaction.cancelled_at),
      order_by: [asc: transaction.id],
      select: transaction.id
    )
    |> Repo.all(log: false)
  end

  def cancel_confirmations(transaction_ids) when is_list(transaction_ids) do
    transaction_ids
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.count(fn transaction_id ->
      {:ok, cancelled?} =
        Repo.transaction(fn ->
          transaction =
            from(transaction in SSOTransaction,
              where: transaction.id == ^transaction_id,
              lock: "FOR UPDATE"
            )
            |> Repo.one(log: false)

          if pending_confirmation?(transaction) do
            clear_confirmation!(transaction, cancelled?: true)
            true
          else
            false
          end
        end)

      cancelled?
    end)
  end

  def identities(%Connection{} = connection) do
    from(identity in Identity,
      where: identity.connection_id == ^connection.id,
      order_by: [asc: identity.inserted_at],
      preload: [:user]
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
  defp failure_user_id(code, user) when code in [:not_member, :identity_conflict],
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

  defp complete_login!(
         transaction,
         connection,
         claims,
         current_user,
         audit_data,
         allow_automatic_linking
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

    case identity do
      nil ->
        case automatic_link_candidate(connection, claims.email) do
          {:ok, email, domain}
          when is_nil(current_user) or current_user.id == email.user_id ->
            if allow_automatic_linking.() do
              begin_confirmed_link!(transaction, connection, claims, email, domain)
            else
              begin_conventional_link!(transaction, claims)
            end

          _other ->
            begin_conventional_link!(transaction, claims)
        end

      %Identity{} = identity ->
        cond do
          current_user && current_user.id != identity.user.id ->
            consume_transaction!(transaction, %{})
            {:reject, :session_user_mismatch}

          locked_member(organization, identity.user) ->
            if current_user do
              notify_email_mismatch? = update_identity_email(identity, claims.email)
              consume_transaction!(transaction, %{})

              insert_audit!(%{audit_data | user: identity.user}, "sso.login", {
                organization,
                %{user_id: identity.user.id, entrypoint: transaction.entrypoint}
              })

              if notify_email_mismatch? do
                enqueue_sso_notification!(
                  "email_mismatch",
                  connection,
                  identity.user,
                  claims.email
                )
              end

              {:login, identity.user, transaction.return_path}
            else
              begin_pending_login!(transaction, connection, identity, claims)
            end

          true ->
            Repo.delete_all(from(candidate in Identity, where: candidate.id == ^identity.id))
            record_failure(connection, :login, :not_member, identity.user)
            consume_transaction!(transaction, %{})
            {:reject, :not_member}
        end
    end
  end

  defp begin_conventional_link!(transaction, claims) do
    link_token = random_token()

    consume_transaction!(transaction, %{
      issuer: claims.issuer,
      subject: claims.subject,
      provider_email: claims.email,
      link_method: "conventional",
      link_token_hash: hash(link_token)
    })

    {:link, transaction.id, link_token, transaction.return_path}
  end

  defp begin_pending_login!(transaction, connection, identity, claims) do
    clear_replaced_pending_logins!(transaction, connection, identity)
    browser_capability = random_token()

    consume_transaction!(transaction, %{
      user_id: identity.user_id,
      issuer: claims.issuer,
      subject: claims.subject,
      provider_email: claims.email,
      link_token_hash: pending_login_capability_hash(browser_capability)
    })

    {:continue, transaction.id, browser_capability, transaction.return_path}
  end

  defp clear_replaced_pending_logins!(transaction, connection, identity) do
    from(candidate in SSOTransaction,
      where: candidate.id != ^transaction.id,
      where: candidate.connection_id == ^connection.id,
      where: candidate.kind == "login",
      where: not is_nil(candidate.consumed_at),
      where: is_nil(candidate.link_method),
      where: candidate.user_id == ^identity.user_id,
      where: candidate.issuer == ^identity.issuer,
      where: candidate.subject == ^identity.subject,
      where: is_nil(candidate.linked_at),
      where: is_nil(candidate.cancelled_at),
      lock: "FOR UPDATE"
    )
    |> Repo.all(log: false)
    |> Enum.each(&clear_pending_login!(&1, cancelled?: true))
  end

  defp automatic_link_candidate(connection, provider_email) when is_binary(provider_email) do
    normalized_email = String.downcase(provider_email)

    with {:ok, domain_name} <- DomainName.from_email(normalized_email),
         %Email{} = email <-
           Repo.one(
             from(email in Email,
               where: email.email == ^normalized_email,
               where: email.primary and email.verified,
               preload: [:user],
               lock: "FOR UPDATE"
             ),
             log: false
           ),
         %OrganizationUser{} <- locked_member(connection.organization, email.user),
         {:ok, domain} <-
           DomainVerification.require_locked_automatic_linking(
             connection.organization,
             domain_name
           ),
         false <-
           Repo.exists?(
             from(identity in Identity,
               where: identity.connection_id == ^connection.id,
               where: identity.user_id == ^email.user_id
             )
           ) do
      {:ok, email, domain}
    else
      _other -> :fallback
    end
  end

  defp automatic_link_candidate(_connection, _provider_email), do: :fallback

  defp begin_confirmed_link!(transaction, connection, claims, email, domain) do
    clear_replaced_confirmations!(transaction, connection, claims, email)
    code = confirmation_code()
    browser_capability = random_token()

    confirmation_expires_at =
      DateTime.add(DateTime.utc_now(), @confirmation_lifetime_seconds, :second)

    consume_transaction!(transaction, %{
      issuer: claims.issuer,
      subject: claims.subject,
      provider_email: claims.email,
      candidate_user_id: email.user_id,
      candidate_email_id: email.id,
      domain_id: domain.id,
      domain_challenge_generation: domain.challenge_generation,
      candidate_connection_version: connection.version,
      link_method: "confirmed_primary_email",
      confirmation_code_hash: confirmation_hash(code),
      confirmation_expires_at: confirmation_expires_at,
      confirmation_attempts: 0,
      confirmation_sends: 1,
      browser_capability_hash: browser_capability_hash(browser_capability)
    })

    enqueue_confirmation_code!(transaction, connection, email, code, confirmation_expires_at)

    {:confirm, transaction.id, browser_capability, transaction.return_path}
  end

  defp clear_replaced_confirmations!(transaction, connection, claims, email) do
    from(candidate in SSOTransaction,
      where: candidate.id != ^transaction.id,
      where: candidate.connection_id == ^connection.id,
      where: candidate.link_method == "confirmed_primary_email",
      where: is_nil(candidate.linked_at),
      where: is_nil(candidate.cancelled_at),
      where:
        (candidate.issuer == ^claims.issuer and candidate.subject == ^claims.subject) or
          candidate.candidate_email_id == ^email.id,
      lock: "FOR UPDATE"
    )
    |> Repo.all(log: false)
    |> Enum.each(&clear_confirmation!(&1, cancelled?: true))
  end

  defp confirmed_link_context(transaction, connection, current_user) do
    with :ok <- require_feature(connection.organization),
         :ok <- require_connection_enabled(connection),
         :ok <- transaction_configuration_available?(transaction, connection),
         true <- transaction.candidate_connection_version == connection.version,
         true <- is_nil(current_user) or current_user.id == transaction.candidate_user_id,
         %Email{} = email <- locked_candidate_email(transaction),
         true <- candidate_email_current?(transaction, email),
         %OrganizationUser{} <- locked_member(connection.organization, email.user),
         {:ok, domain_name} <- DomainName.from_email(email.email),
         {:ok, domain} <-
           DomainVerification.require_locked_automatic_linking(
             connection.organization,
             domain_name
           ),
         true <- domain.id == transaction.domain_id,
         true <- domain.challenge_generation == transaction.domain_challenge_generation,
         false <- confirmed_identity_conflict?(transaction, connection, email) do
      {:ok, email, domain}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :confirmation_context_changed}
    end
  end

  defp locked_candidate_email(transaction) do
    from(email in Email,
      where: email.id == ^transaction.candidate_email_id,
      where: email.user_id == ^transaction.candidate_user_id,
      lock: "FOR UPDATE",
      preload: [:user]
    )
    |> Repo.one(log: false)
  end

  defp candidate_email_current?(transaction, email) do
    is_binary(transaction.provider_email) and email.primary and email.verified and
      email.email == String.downcase(transaction.provider_email)
  end

  defp confirmed_identity_conflict?(transaction, connection, email) do
    Repo.exists?(
      from(identity in Identity,
        where: identity.connection_id == ^connection.id,
        where:
          identity.user_id == ^email.user_id or
            (identity.issuer == ^transaction.issuer and
               identity.subject == ^transaction.subject)
      )
    )
  end

  defp insert_confirmed_identity!(transaction, connection, email, audit_data) do
    identity =
      Identity.changeset(%Identity{}, %{
        organization_id: connection.organization.id,
        connection_id: connection.id,
        user_id: email.user_id,
        issuer: transaction.issuer,
        subject: transaction.subject,
        provider_email: transaction.provider_email,
        link_method: "confirmed_primary_email"
      })

    case Repo.insert(identity, log: false) do
      {:ok, identity} ->
        clear_confirmation!(transaction, linked?: true)

        insert_audit!(%{audit_data | user: email.user}, "sso.identity.link", {
          connection.organization,
          %{
            user_id: email.user_id,
            entrypoint: transaction.entrypoint,
            link_method: "confirmed_primary_email"
          }
        })

        insert_audit!(%{audit_data | user: email.user}, "sso.login", {
          connection.organization,
          %{user_id: email.user_id, entrypoint: transaction.entrypoint}
        })

        enqueue_sso_notification!("identity_linked", connection, email.user)

        {:confirmed, identity, email.user, connection.organization, transaction.return_path}

      {:error, _changeset} ->
        clear_confirmation!(transaction, cancelled?: true)
        {:error, :fresh_login_required}
    end
  end

  defp pending_login_context(transaction, connection, current_user) do
    identity =
      from(identity in Identity,
        where: identity.connection_id == ^connection.id,
        where: identity.issuer == ^transaction.issuer,
        where: identity.subject == ^transaction.subject,
        lock: "FOR UPDATE",
        preload: [user: :emails]
      )
      |> Repo.one(log: false)

    with :ok <- require_feature(connection.organization),
         :ok <- require_connection_enabled(connection),
         :ok <- transaction_configuration_available?(transaction, connection),
         true <- transaction.issuer == connection.issuer,
         %Identity{} = identity <- identity,
         true <- identity.user_id == transaction.user_id,
         true <- is_nil(current_user) or current_user.id == identity.user_id,
         %OrganizationUser{} <- locked_member(connection.organization, identity.user) do
      {:ok, identity}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :pending_login_context_changed}
    end
  end

  defp pending_login_capability_available?(transaction, browser_capability) do
    cond do
      transaction.kind != "login" ->
        {:error, :invalid_pending_login}

      is_nil(transaction.consumed_at) ->
        {:error, :invalid_pending_login}

      not is_nil(transaction.link_method) or not is_integer(transaction.user_id) ->
        {:error, :invalid_pending_login}

      transaction.linked_at ->
        {:error, :pending_login_already_used}

      transaction.cancelled_at ->
        {:error, :pending_login_cancelled}

      not secure_pending_login_capability_match?(
        transaction.link_token_hash,
        browser_capability
      ) ->
        {:error, :invalid_pending_login}

      true ->
        :ok
    end
  end

  defp pending_login_expired?(%SSOTransaction{expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  defp pending_login_expired?(_transaction), do: true

  defp clear_pending_login!(transaction, opts \\ []) do
    attrs = %{
      user_id: nil,
      issuer: nil,
      subject: nil,
      provider_email: nil,
      link_token_hash: nil
    }

    attrs =
      if Keyword.get(opts, :cancelled?, false) do
        Map.put(attrs, :cancelled_at, DateTime.utc_now())
      else
        attrs
      end

    Repo.update!(SSOTransaction.consume_changeset(transaction, attrs), log: false)
  end

  defp confirmation_available?(transaction, browser_capability) do
    with :ok <- confirmation_capability_available?(transaction, browser_capability) do
      cond do
        transaction.confirmation_verified_at ->
          {:error, :confirmation_already_verified}

        confirmation_expired?(transaction) ->
          {:error, :confirmation_expired}

        transaction.confirmation_attempts >= @confirmation_max_attempts ->
          {:error, :confirmation_attempts_exhausted}

        true ->
          :ok
      end
    end
  end

  defp confirmation_capability_available?(transaction, browser_capability) do
    cond do
      transaction.kind != "login" ->
        {:error, :invalid_confirmation}

      is_nil(transaction.consumed_at) ->
        {:error, :invalid_confirmation}

      transaction.link_method != "confirmed_primary_email" ->
        {:error, :invalid_confirmation}

      transaction.linked_at ->
        {:error, :confirmation_already_used}

      transaction.cancelled_at ->
        {:error, :confirmation_cancelled}

      not secure_browser_capability_match?(
        transaction.browser_capability_hash,
        browser_capability
      ) ->
        {:error, :invalid_confirmation}

      true ->
        :ok
    end
  end

  defp confirmation_expired?(%SSOTransaction{
         confirmation_expires_at: %DateTime{} = expires_at
       }) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  defp confirmation_expired?(_transaction), do: true

  defp verified_confirmation_available?(transaction, browser_capability) do
    with :ok <- confirmation_capability_available?(transaction, browser_capability) do
      cond do
        is_nil(transaction.confirmation_verified_at) ->
          {:error, :confirmation_not_verified}

        confirmation_expired?(transaction) ->
          {:error, :confirmation_expired}

        true ->
          :ok
      end
    end
  end

  defp pending_confirmation?(%SSOTransaction{} = transaction) do
    transaction.link_method == "confirmed_primary_email" and is_nil(transaction.linked_at) and
      is_nil(transaction.cancelled_at)
  end

  defp pending_confirmation?(_transaction), do: false

  defp pending_confirmation_context_current?(transaction) do
    connection = transaction.connection
    organization = connection.organization
    domain = transaction.domain
    email = transaction.candidate_email
    user = transaction.candidate_user

    with true <- Features.enabled?(organization),
         true <- Connection.enabled?(connection),
         :ok <- transaction_configuration_available?(transaction, connection),
         true <- transaction.candidate_connection_version == connection.version,
         %Email{} <- email,
         true <- email.user_id == transaction.candidate_user_id,
         true <- candidate_email_current?(transaction, email),
         %{id: user_id} <- user,
         true <- user_id == transaction.candidate_user_id,
         true <- current_member?(organization, user),
         {:ok, domain_name} <- DomainName.from_email(email.email),
         %{} <- domain,
         true <- domain.organization_id == organization.id,
         true <- domain.domain == domain_name,
         true <- domain.state == "verified",
         true <- domain.automatic_linking_enabled,
         true <- domain.challenge_generation == transaction.domain_challenge_generation,
         true <- DomainVerification.valid_lease?(domain) do
      true
    else
      _other -> false
    end
  end

  defp cancel_connection_confirmations!(%Connection{id: connection_id})
       when is_integer(connection_id) do
    connection_id
    |> pending_connection_confirmation_ids()
    |> cancel_confirmations()
  end

  defp current_member?(organization, user) do
    Repo.exists?(
      from(organization_user in OrganizationUser,
        where: organization_user.organization_id == ^organization.id,
        where: organization_user.user_id == ^user.id
      )
    )
  end

  defp expire_confirmation(transaction_id) do
    Repo.transaction(fn ->
      transaction =
        from(transaction in SSOTransaction,
          where: transaction.id == ^transaction_id,
          lock: "FOR UPDATE"
        )
        |> Repo.one(log: false)

      if transaction && confirmation_expired?(transaction) && is_nil(transaction.linked_at) &&
           is_nil(transaction.cancelled_at) do
        clear_confirmation!(transaction, cancelled?: true)
      end
    end)
  end

  defp mark_confirmation_verified!(transaction) do
    delete_confirmation_email!(transaction)
    verified_at = DateTime.utc_now()

    Repo.update!(
      SSOTransaction.consume_changeset(transaction, %{
        confirmation_code_hash: nil,
        confirmation_verified_at: verified_at,
        confirmation_expires_at:
          DateTime.add(verified_at, @verified_confirmation_lifetime_seconds, :second)
      }),
      log: false
    )
  end

  defp clear_confirmation!(transaction, opts) do
    delete_confirmation_email!(transaction)

    attrs = %{
      candidate_user_id: nil,
      candidate_email_id: nil,
      domain_id: nil,
      domain_challenge_generation: nil,
      candidate_connection_version: nil,
      confirmation_code_hash: nil,
      confirmation_expires_at: nil,
      confirmation_verified_at: nil,
      confirmation_attempts: 0,
      confirmation_sends: 0,
      browser_capability_hash: nil,
      issuer: nil,
      subject: nil,
      provider_email: nil,
      link_token_hash: nil
    }

    attrs =
      cond do
        Keyword.get(opts, :linked?, false) ->
          Map.put(attrs, :linked_at, DateTime.utc_now())

        Keyword.get(opts, :cancelled?, false) ->
          Map.put(attrs, :cancelled_at, DateTime.utc_now())

        true ->
          attrs
      end

    Repo.update!(SSOTransaction.consume_changeset(transaction, attrs), log: false)
  end

  defp enqueue_confirmation_code!(transaction, connection, email, code, expires_at) do
    Outbox.enqueue!(
      Emails.sso_confirmation_code(
        connection.organization.name,
        email.user.username,
        email.email,
        code
      ),
      category: @confirmation_code_category,
      ordering_key: confirmation_ordering_key(transaction),
      scope_key: confirmation_scope_key(connection, email.user),
      expires_at: expires_at
    )
  end

  defp delete_confirmation_email!(transaction) do
    ordering_key = confirmation_ordering_key(transaction)
    OutboxLock.acquire!(ordering_key)

    Repo.delete_all(
      from(entry in OutboxEntry,
        where: entry.ordering_key == ^ordering_key,
        where: entry.category == @confirmation_code_category
      ),
      log: false
    )
  end

  defp lock_confirmation_outbox!(query) do
    from(entry in query, select: entry.ordering_key, distinct: true)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
    |> Enum.each(&OutboxLock.acquire!/1)
  end

  defp confirmation_ordering_key(transaction), do: "sso-confirmation:#{transaction.id}"

  defp confirmation_scope_key(connection, user),
    do: "sso-confirmation:user:#{user.id}:connection:#{connection.id}"

  defp confirmation_code do
    7
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(padding: false)
    |> binary_part(0, 10)
  end

  defp normalize_confirmation_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> String.upcase()
  end

  defp normalize_confirmation_code(_code), do: ""

  defp confirmation_hash(code), do: keyed_hash("sso-confirmation-code:", code)
  defp browser_capability_hash(capability), do: keyed_hash("sso-browser-capability:", capability)

  defp pending_login_capability_hash(capability),
    do: keyed_hash("sso-login-capability:", capability)

  defp secure_confirmation_match?(stored_hash, code)
       when is_binary(stored_hash) and is_binary(code) do
    Plug.Crypto.secure_compare(stored_hash, confirmation_hash(code))
  end

  defp secure_confirmation_match?(_stored_hash, _code), do: false

  defp secure_browser_capability_match?(stored_hash, capability)
       when is_binary(stored_hash) and is_binary(capability) do
    Plug.Crypto.secure_compare(stored_hash, browser_capability_hash(capability))
  end

  defp secure_browser_capability_match?(_stored_hash, _capability), do: false

  defp secure_pending_login_capability_match?(stored_hash, capability)
       when is_binary(stored_hash) and is_binary(capability) do
    Plug.Crypto.secure_compare(stored_hash, pending_login_capability_hash(capability))
  end

  defp secure_pending_login_capability_match?(_stored_hash, _capability), do: false

  defp keyed_hash(purpose, value) do
    :crypto.mac(
      :hmac,
      :sha256,
      Application.fetch_env!(:hexpm, :secret),
      purpose <> value
    )
  end

  defp unwrap_confirmation_result({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_confirmation_result({:ok, result}), do: {:ok, result}
  defp unwrap_confirmation_result({:error, reason}), do: {:error, reason}

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

  defp require_entrypoint(_organization, "organization", nil), do: :ok
  defp require_entrypoint(_organization, "third_party", nil), do: :ok

  defp require_entrypoint(organization, "discovery", domain_name) when is_binary(domain_name) do
    if DomainVerification.discovery_available?(organization, domain_name),
      do: :ok,
      else: {:error, :domain_not_verified}
  end

  defp require_entrypoint(_organization, _entrypoint, _domain_name),
    do: {:error, :invalid_entrypoint}

  defp require_locked_entrypoint(_organization, "organization", nil), do: :ok
  defp require_locked_entrypoint(_organization, "third_party", nil), do: :ok

  defp require_locked_entrypoint(organization, "discovery", domain_name)
       when is_binary(domain_name) do
    DomainVerification.require_locked_discovery(organization, domain_name)
  end

  defp require_locked_entrypoint(_organization, _entrypoint, _domain_name),
    do: {:error, :invalid_entrypoint}

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

      transaction.link_method != "conventional" ->
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
    recipients = Repo.all(from(email in assoc(user, :emails), select: email.email))

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

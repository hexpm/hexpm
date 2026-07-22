defmodule Hexpm.Accounts.SSO do
  use Hexpm.Context

  alias Hexpm.Accounts.SSO.{Connection, Error, Failure, Features, Identity, Notification, OIDC}
  alias Hexpm.Accounts.SSO.SafeURL
  alias Hexpm.Accounts.SSO.Transaction, as: SSOTransaction
  alias Hexpm.Accounts.OrganizationUser
  alias Hexpm.Emails.SSONotificationWorker

  @transaction_lifetime_seconds 10 * 60
  @diagnostic_limit 20

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

      issuer_changed_with_identities?(connection, issuer) ->
        {:error, :connection_has_identities}

      true ->
        changeset = Connection.credentials_changeset(connection, attrs)

        with {:ok, connection} <- validate_changeset(changeset),
             {:ok, _uri} <- SafeURL.validate_syntax(connection.issuer),
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

      if issuer_changed_with_identities?(connection, desired.issuer) do
        Hexpm.RepoBase.rollback(:connection_has_identities)
      end

      attrs =
        metadata
        |> Map.merge(%{
          organization_id: organization.id,
          issuer: desired.issuer,
          client_id: desired.client_id,
          client_secret: supplied_secret || connection.client_secret,
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

        if current.version == connection.version and current.issuer == connection.issuer do
          current
          |> Connection.configuration_changeset(Map.put(metadata, :version, current.version + 1))
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

  def start_login(organization, return_path, redirect_uri) do
    with :ok <- require_feature(organization),
         %Connection{} = connection <- get_connection(organization),
         true <- Connection.enabled?(connection),
         {:ok, connection} <- refresh_metadata_if_expired(connection),
         {:ok, {transaction, uri}} <-
           Repo.transaction(fn ->
             connection = locked_connection!(connection.id)

             with :ok <- require_feature(connection.organization),
                  :ok <- require_connection_enabled(connection),
                  {:ok, transaction, state} <-
                    create_transaction(
                      connection,
                      nil,
                      "login",
                      "active",
                      redirect_uri,
                      return_path
                    ),
                  transaction = %{transaction | raw_state: state},
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
         {:ok, connection} <- refresh_metadata_if_expired(connection),
         {:ok, {transaction, uri}} <-
           Repo.transaction(fn ->
             connection = locked_connection!(connection.id)

             with :ok <- require_feature(connection.organization),
                  :ok <- require_locked_admin(connection.organization, user),
                  {:ok, client_secret} <- secret_for_slot(connection, secret_slot),
                  {:ok, transaction, state} <-
                    create_transaction(
                      connection,
                      user,
                      "test",
                      secret_slot,
                      redirect_uri,
                      nil
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

  def complete_callback(transaction, claims, current_user, audit_data) do
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
            "test" -> complete_test!(transaction, connection, current_user, audit_data)
            "login" -> complete_login!(transaction, connection, claims, audit_data)
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
                %{user_id: user.id}
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
        Multi.delete_all(
          multi,
          :organization_sso_notifications,
          from(notification in Notification,
            where: notification.connection_id == ^connection.id,
            where: notification.user_id == ^user.id,
            where: notification.kind in ["email_mismatch", "identity_linked"]
          )
        )
    end
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
      limit: @diagnostic_limit
    )
    |> Repo.all()
  end

  def record_failure(%Connection{} = connection, %Error{} = error) do
    attrs = %{
      connection_id: connection.id,
      stage: to_string(stable_failure_code(error.stage)),
      code: to_string(stable_failure_code(error.code)),
      details: redact_details(error.details)
    }

    with {:ok, failure} <- Repo.insert(Failure.changeset(%Failure{}, attrs)) do
      keep_recent_failures(connection)
      {:ok, failure}
    end
  end

  def record_failure(%Connection{} = connection, stage, code) do
    record_failure(connection, %Error{stage: stage, code: stable_failure_code(code)})
  end

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

  defp complete_login!(transaction, connection, claims, audit_data) do
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
        link_token = random_token()

        consume_transaction!(transaction, %{
          issuer: claims.issuer,
          subject: claims.subject,
          provider_email: claims.email,
          link_token_hash: hash(link_token)
        })

        {:link, transaction.id, link_token, transaction.return_path}

      %Identity{} = identity ->
        if locked_member(organization, identity.user) do
          notify_email_mismatch? = update_identity_email(identity, claims.email)
          consume_transaction!(transaction, %{})

          insert_audit!(%{audit_data | user: identity.user}, "sso.login", {
            organization,
            %{user_id: identity.user.id}
          })

          if notify_email_mismatch? do
            enqueue_sso_notification!(
              "email_mismatch",
              connection,
              identity.user,
              claims.email
            )
          end

          {:login, identity.user, notify_email_mismatch?, claims.email, transaction.return_path}
        else
          Repo.delete_all(from(candidate in Identity, where: candidate.id == ^identity.id))
          record_failure(connection, :login, :not_member)
          consume_transaction!(transaction, %{})
          {:reject, :not_member}
        end
    end
  end

  defp create_transaction(connection, user, kind, secret_slot, redirect_uri, return_path) do
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
      expires_at: DateTime.add(DateTime.utc_now(), @transaction_lifetime_seconds, :second)
    }

    case Repo.insert(SSOTransaction.changeset(%SSOTransaction{}, attrs), log: false) do
      {:ok, transaction} -> {:ok, transaction, state}
      {:error, changeset} -> {:error, changeset}
    end
  end

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

    notification =
      %Notification{}
      |> Notification.changeset(%{
        connection_id: connection.id,
        user_id: user.id,
        kind: kind,
        organization_name: connection.organization.name,
        username: user.username,
        recipients: %{emails: recipients},
        provider_email: provider_email
      })
      |> Repo.insert!(log: false)

    SSONotificationWorker.enqueue!(notification.id)
  end

  defp delete_notifications!(connection, user) do
    Repo.delete_all(
      from(notification in Notification,
        where: notification.connection_id == ^connection.id,
        where: notification.user_id == ^user.id,
        where: notification.kind in ["email_mismatch", "identity_linked"]
      )
    )
  end

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

  defp issuer_changed_with_identities?(%Connection{id: nil}, _issuer), do: false

  defp issuer_changed_with_identities?(%Connection{} = connection, issuer) do
    connection.issuer != issuer and
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
      "issuer_mismatch" => "The provider issuer did not match the configured issuer",
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
    decoded_path = URI.decode(path)
    segments = String.split(decoded_path, "/")

    not String.contains?(decoded_path, ["\\", "\r", "\n", "\t"]) and
      not Enum.any?(segments, &(&1 in [".", ".."])) and
      (decoded_path == organization_path or
         String.starts_with?(decoded_path, organization_path <> "/"))
  rescue
    _exception -> false
  end

  defp allowed_organization_path?(_path, _organization_path), do: false

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

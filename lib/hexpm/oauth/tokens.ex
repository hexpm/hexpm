defmodule Hexpm.OAuth.Tokens do
  use Hexpm.Context

  alias Hexpm.OAuth.{Token, Clients, JWT}
  alias Hexpm.Permissions

  @default_expires_in 30 * 60
  @default_refresh_token_expires_in 30 * 24 * 60 * 60
  @restricted_refresh_token_expires_in 60 * 60

  @doc """
  Looks up a token by its value and type.

  ## Options
    * `:client_id` - Require token to belong to specific client
    * `:validate` - Check if token is valid (not expired/revoked), defaults to true
    * `:preload` - List of associations to preload, defaults to [:user]

  ## Returns
    * `{:ok, token}` - Token found and valid
    * `{:error, reason}` - Token not found, invalid, or validation failed
  """
  def lookup(jwt_token, type, opts \\ []) when type in [:access, :refresh] do
    client_id = Keyword.get(opts, :client_id)
    validate = Keyword.get(opts, :validate, true)
    preload = Keyword.get(opts, :preload, [:user])

    with {:ok, claims} <- JWT.verify_and_decode(jwt_token),
         {:ok, jti} <- extract_jti_for_type(claims, type),
         {:ok, token} <- find_token_by_jti(jti, type, client_id),
         :ok <- maybe_validate(token, validate, type),
         token <- maybe_preload(token, preload) do
      {:ok, token}
    else
      {:error, :signature_error} -> {:error, :invalid_token}
      {:error, [message: "Invalid token", claim: "exp", claim_val: _]} -> {:error, :token_invalid}
      other -> other
    end
  end

  @doc """
  Creates a token for a user with the given client and scopes.
  """
  def create_for_user(user, client_id, scopes, grant_type, grant_reference \\ nil, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    jwt_opts = [
      session_id: Keyword.get(opts, :session_id),
      parent_jti: get_parent_jti(opts),
      expires_in: expires_in
    ]

    {:ok, access_token, jti} = JWT.generate_access_token(user.username, "user", scopes, jwt_opts)

    attrs = %{
      jti: jti,
      access_token: access_token,
      scopes: scopes,
      expires_at: expires_at,
      grant_type: grant_type,
      grant_reference: grant_reference,
      user_id: user.id,
      client_id: client_id,
      session_id: Keyword.get(opts, :session_id),
      parent_token_id: Keyword.get(opts, :parent_token_id)
    }

    attrs =
      if Keyword.get(opts, :with_refresh_token, false) do
        # Determine refresh token expiration based on scopes
        refresh_expires_in =
          if has_write_scope?(scopes) do
            @restricted_refresh_token_expires_in
          else
            @default_refresh_token_expires_in
          end

        refresh_expires_at = DateTime.add(DateTime.utc_now(), refresh_expires_in, :second)

        refresh_opts = [
          session_id: Keyword.get(opts, :session_id),
          expires_in: refresh_expires_in
        ]

        {:ok, refresh_token, refresh_jti} =
          JWT.generate_refresh_token(user.username, "user", scopes, refresh_opts)

        Map.merge(attrs, %{
          refresh_jti: refresh_jti,
          refresh_token: refresh_token,
          refresh_token_expires_at: refresh_expires_at
        })
      else
        attrs
      end

    Token.build(attrs)
  end

  @doc """
  Creates and inserts a token for a user.
  """
  def create_and_insert_for_user(
        user,
        client_id,
        scopes,
        grant_type,
        grant_reference \\ nil,
        opts \\ []
      ) do
    changeset = create_for_user(user, client_id, scopes, grant_type, grant_reference, opts)
    Repo.insert(changeset)
  end

  @doc """
  Creates a session and token for a user atomically within a transaction.
  """
  def create_session_and_token_for_user(
        user,
        client_id,
        scopes,
        grant_type,
        grant_reference \\ nil,
        opts \\ []
      ) do
    alias Hexpm.OAuth.Sessions

    Ecto.Multi.new()
    |> Ecto.Multi.run(:session, fn _repo, _changes ->
      Sessions.create_for_user(user, client_id, name: Keyword.get(opts, :name))
    end)
    |> Ecto.Multi.run(:token, fn _repo, %{session: session} ->
      token_opts = Keyword.put(opts, :session_id, session.id)

      changeset =
        create_for_user(user, client_id, scopes, grant_type, grant_reference, token_opts)

      Repo.insert(changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Revokes an old token and creates a new one atomically within a transaction.
  Used for refresh token grant to ensure the old token is only revoked if the new one is created successfully.
  """
  def revoke_and_create_token(
        old_token,
        client_id,
        scopes,
        grant_type,
        grant_reference \\ nil,
        opts \\ []
      ) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:revoked_token, revoke_changeset(old_token))
    |> Ecto.Multi.run(:new_token, fn _repo, _changes ->
      changeset =
        create_for_user(old_token.user, client_id, scopes, grant_type, grant_reference, opts)

      Repo.insert(changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{new_token: token}} -> {:ok, token}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Creates an exchanged token from a parent token with subset scopes.
  Always creates children of the root token to maintain a flat hierarchy.
  """
  def create_exchanged_token(parent_token, client_id, target_scopes, grant_reference) do
    # Preload user if not already loaded
    parent_token = Repo.preload(parent_token, :user)

    # Find the root token (the one without a parent_token_id)
    root_token_id =
      if parent_token.parent_token_id do
        # If parent has a parent, use parent's parent (which should be the root)
        parent_token.parent_token_id
      else
        # Parent is already the root
        parent_token.id
      end

    opts = [
      session_id: parent_token.session_id,
      parent_token_id: root_token_id,
      expires_in: DateTime.diff(parent_token.expires_at, DateTime.utc_now()),
      with_refresh_token: not is_nil(parent_token.refresh_jti)
    ]

    create_for_user(
      parent_token.user,
      client_id,
      target_scopes,
      "urn:ietf:params:oauth:grant-type:token-exchange",
      grant_reference,
      opts
    )
  end

  @doc """
  Revokes a single token without affecting the session.
  To revoke all tokens in a session, use Sessions.revoke/1.
  """
  def revoke(%Token{} = token) do
    token
    |> Token.changeset(%{revoked_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Returns a changeset for revoking a token (for backward compatibility).
  """
  def revoke_changeset(%Token{} = token) do
    Token.changeset(token, %{revoked_at: DateTime.utc_now()})
  end

  @doc """
  Checks if the token is expired.
  """
  def expired?(%Token{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the refresh token is expired.
  """
  def refresh_token_expired?(%Token{refresh_token_expires_at: nil}), do: false

  def refresh_token_expired?(%Token{refresh_token_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the token is revoked.
  """
  def revoked?(%Token{revoked_at: nil}), do: false
  def revoked?(%Token{revoked_at: _}), do: true

  @doc """
  Checks if the token is valid (not expired and not revoked).
  """
  def valid?(%Token{} = token) do
    not expired?(token) and not revoked?(token)
  end

  @doc """
  Checks if the refresh token is valid (not expired and not revoked).
  """
  def refresh_token_valid?(%Token{} = token) do
    not refresh_token_expired?(token) and not revoked?(token)
  end

  @doc """
  Validates that the token has the required scopes.
  """
  def has_scopes?(%Token{scopes: token_scopes}, required_scopes) do
    Enum.all?(required_scopes, &(&1 in token_scopes))
  end

  @doc """
  Checks if the scopes include write permissions (api or api:write).
  """
  def has_write_scope?(scopes) do
    "api" in scopes or "api:write" in scopes
  end

  @doc """
  Cleans up expired OAuth tokens.
  This should be called periodically to remove old records.
  """
  def cleanup_expired_tokens do
    now = DateTime.utc_now()

    from(t in Token,
      where: t.expires_at < ^now and is_nil(t.revoked_at)
    )
    |> Repo.delete_all()
  end

  defp get_parent_jti(opts) do
    case Keyword.get(opts, :parent_token_id) do
      nil ->
        nil

      parent_id ->
        case Repo.get(Token, parent_id) do
          %Token{jti: jti} -> jti
          _ -> nil
        end
    end
  end

  defp extract_jti_for_type(claims, :access) do
    case claims do
      %{"jti" => jti} -> {:ok, jti}
      _ -> {:error, :invalid_token}
    end
  end

  defp extract_jti_for_type(claims, :refresh) do
    case claims do
      %{"jti" => jti} -> {:ok, jti}
      _ -> {:error, :invalid_token}
    end
  end

  defp find_token_by_jti(jti, :access, client_id) do
    query =
      if client_id do
        Repo.get_by(Token, jti: jti, client_id: client_id)
      else
        Repo.get_by(Token, jti: jti)
      end

    case query do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp find_token_by_jti(jti, :refresh, client_id) do
    query =
      if client_id do
        Repo.get_by(Token, refresh_jti: jti, client_id: client_id)
      else
        Repo.get_by(Token, refresh_jti: jti)
      end

    case query do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp maybe_validate(token, true, :access) do
    if valid?(token) do
      :ok
    else
      {:error, :token_invalid}
    end
  end

  defp maybe_validate(token, true, :refresh) do
    if refresh_token_valid?(token) do
      :ok
    else
      {:error, :token_invalid}
    end
  end

  defp maybe_validate(_token, false, _type), do: :ok

  defp maybe_preload(token, []), do: token
  defp maybe_preload(token, preload), do: Repo.preload(token, preload)

  # Token Exchange (RFC 8693) functionality

  @doc """
  Exchanges a subject token for a new token with target scopes.

  Parameters:
  - client_id: The OAuth client requesting the exchange
  - subject_token: The token being exchanged (access token or refresh token)
  - subject_token_type: Type of the subject token:
    - "urn:ietf:params:oauth:token-type:access_token" for access tokens
    - "urn:ietf:params:oauth:token-type:refresh_token" for refresh tokens
  - target_scopes: List of scopes for the new token (must be subset of subject token scopes)

  Returns:
  - {:ok, new_token} on success
  - {:error, error_type, description} on failure
  """
  def exchange_token(client_id, subject_token, subject_token_type, target_scopes) do
    with {:ok, _client} <- validate_exchange_client(client_id),
         {:ok, parent_token} <-
           validate_subject_token(subject_token, subject_token_type, client_id),
         {:ok, validated_scopes} <- validate_target_scopes(parent_token.scopes, target_scopes),
         {:ok, token_changeset} <-
           create_exchange_token(parent_token, client_id, validated_scopes, subject_token) do
      case Repo.insert(token_changeset) do
        {:ok, new_token} ->
          {:ok, new_token}

        {:error, changeset} ->
          {:error, :server_error,
           "Failed to create exchanged token: #{inspect(changeset.errors)}"}
      end
    end
  end

  defp validate_exchange_client(client_id) do
    case Clients.get(client_id) do
      nil -> {:error, :invalid_client, "Invalid client"}
      client -> {:ok, client}
    end
  end

  defp validate_subject_token(subject_token, subject_token_type, client_id) do
    case subject_token_type do
      "urn:ietf:params:oauth:token-type:access_token" ->
        lookup_access_token(subject_token, client_id)

      "urn:ietf:params:oauth:token-type:refresh_token" ->
        lookup_refresh_token(subject_token, client_id)

      unsupported_type ->
        {:error, :invalid_request, "Unsupported subject_token_type: #{unsupported_type}"}
    end
  end

  defp lookup_access_token(user_access_token, client_id) do
    case lookup(user_access_token, :access, client_id: client_id) do
      {:ok, token} ->
        {:ok, token}

      {:error, :not_found} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :invalid_token} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :token_invalid} ->
        {:error, :invalid_grant, "Subject token expired or revoked"}

      {:error, _} ->
        # JWT verification errors should be treated as invalid token
        {:error, :invalid_grant, "Invalid subject token"}
    end
  end

  defp lookup_refresh_token(user_refresh_token, client_id) do
    case lookup(user_refresh_token, :refresh, client_id: client_id) do
      {:ok, token} ->
        {:ok, token}

      {:error, :not_found} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :invalid_token} ->
        {:error, :invalid_grant, "Invalid subject token"}

      {:error, :token_invalid} ->
        {:error, :invalid_grant, "Subject token expired or revoked"}

      {:error, _} ->
        # JWT verification errors should be treated as invalid token
        {:error, :invalid_grant, "Invalid subject token"}
    end
  end

  defp validate_target_scopes(source_scopes, target_scopes) when is_list(target_scopes) do
    case Permissions.validate_scope_subset(source_scopes, target_scopes) do
      :ok -> {:ok, target_scopes}
      {:error, message} -> {:error, :invalid_scope, message}
    end
  end

  defp validate_target_scopes(source_scopes, target_scopes) when is_binary(target_scopes) do
    target_scope_list = String.split(target_scopes, " ", trim: true)
    validate_target_scopes(source_scopes, target_scope_list)
  end

  defp validate_target_scopes(_source_scopes, nil) do
    {:error, :invalid_request, "Missing required parameter: scope"}
  end

  defp create_exchange_token(parent_token, client_id, target_scopes, grant_reference) do
    token_changeset =
      create_exchanged_token(parent_token, client_id, target_scopes, grant_reference)

    {:ok, token_changeset}
  end
end

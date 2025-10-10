defmodule Hexpm.OAuth.Tokens do
  use Hexpm.Context

  alias Hexpm.OAuth.{Token, JWT}
  alias Hexpm.Permissions

  @default_expires_in 30 * 60
  @default_refresh_token_expires_in 30 * 24 * 60 * 60

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

    # Expand "repositories" scope to individual "repository:{org}" scopes for access tokens
    # This allows edge verification without database lookups
    expanded_scopes = Permissions.expand_repositories_scope(user, scopes)

    jwt_opts = [
      session_id: Keyword.get(opts, :user_session_id),
      expires_in: expires_in
    ]

    {:ok, access_token, jti} =
      JWT.generate_access_token(user.username, "user", expanded_scopes, jwt_opts)

    attrs = %{
      jti: jti,
      access_token: access_token,
      scopes: expanded_scopes,
      expires_at: expires_at,
      grant_type: grant_type,
      grant_reference: grant_reference,
      user_id: user.id,
      client_id: client_id,
      user_session_id: Keyword.get(opts, :user_session_id)
    }

    attrs =
      if Keyword.get(opts, :with_refresh_token, false) do
        refresh_expires_at =
          DateTime.add(DateTime.utc_now(), @default_refresh_token_expires_in, :second)

        refresh_opts = [
          session_id: Keyword.get(opts, :user_session_id),
          expires_in: @default_refresh_token_expires_in
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
    alias Hexpm.UserSessions

    Ecto.Multi.new()
    |> Ecto.Multi.run(:session, fn _repo, _changes ->
      UserSessions.create_oauth_session(user, client_id, name: Keyword.get(opts, :name))
    end)
    |> Ecto.Multi.run(:update_session_last_use, fn _repo, %{session: session} ->
      if Keyword.has_key?(opts, :usage_info) do
        UserSessions.update_last_use(session, Keyword.get(opts, :usage_info))
      else
        {:ok, session}
      end
    end)
    |> Ecto.Multi.run(:token, fn _repo, %{update_session_last_use: session} ->
      token_opts = Keyword.put(opts, :user_session_id, session.id)

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
    alias Hexpm.UserSessions

    Ecto.Multi.new()
    |> Ecto.Multi.update(:revoked_token, revoke_changeset(old_token))
    |> Ecto.Multi.run(:new_token, fn _repo, _changes ->
      changeset =
        create_for_user(old_token.user, client_id, scopes, grant_type, grant_reference, opts)

      Repo.insert(changeset)
    end)
    |> Ecto.Multi.run(:update_session_last_use, fn _repo, %{new_token: new_token} ->
      # Update session's last_use when token is refreshed
      if new_token.user_session_id && Keyword.has_key?(opts, :usage_info) do
        case Repo.get(Hexpm.UserSession, new_token.user_session_id) do
          nil ->
            {:ok, nil}

          session ->
            UserSessions.update_last_use(session, Keyword.get(opts, :usage_info))
        end
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{new_token: token}} -> {:ok, token}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
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
end

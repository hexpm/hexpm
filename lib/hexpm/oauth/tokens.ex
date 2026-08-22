defmodule Hexpm.OAuth.Tokens do
  use Hexpm.Context

  alias Hexpm.{UserSession, UserSessions}
  alias Hexpm.OAuth.{AuthorizationCodes, Token, JWT}
  alias Hexpm.Permissions

  @default_expires_in 30 * 60
  @default_refresh_token_expires_in 30 * 24 * 60 * 60

  @doc """
  Computes SHA256 hash of a refresh token, hex-encoded lowercase.
  """
  def hash_refresh_token(refresh_token) when is_binary(refresh_token) do
    :crypto.hash(:sha256, refresh_token)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Looks up a token by its refresh token hash.
  The hash should be a hex-encoded SHA256 hash of the refresh token.

  Returns {:ok, token} if found, {:error, :not_found} otherwise.
  """
  def lookup_by_refresh_token_hash(hash) when is_binary(hash) do
    normalized_hash = String.downcase(hash)

    case Repo.get_by(Token, refresh_token_hash: normalized_hash) do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  @doc """
  Looks up a token by its value and type.

  ## Options
    * `:client_id` - Require token to belong to specific client
    * `:validate` - Check if token is valid (not expired/revoked), defaults to true
    * `:preload` - List of associations to preload, defaults to [:user]

  ## Returns
    * `{:ok, token}` - Token found and valid
    * `{:error, reason}` - Token not found, invalid, or validation failed

  A validated token also has to belong to a live session, so revoking a session
  takes effect on the next request even for a token the revocation missed.
  """
  def lookup(jwt_token, type, opts \\ []) when type in [:access, :refresh] do
    client_id = Keyword.get(opts, :client_id)
    validate = Keyword.get(opts, :validate, true)
    preload = Keyword.get(opts, :preload, [:user])

    with {:ok, claims} <- JWT.verify_and_decode(jwt_token),
         {:ok, jti} <- extract_jti_for_type(claims, type),
         {:ok, token, session_live?} <- find_token_by_jti(jti, type, client_id),
         :ok <- maybe_validate(token, session_live?, validate, type),
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

    # "repositories" is expanded into individual "repository:{org}" scopes so the
    # edge can verify them without a database lookup, and the organizations this
    # session has not authenticated for are then dropped: the scope the token
    # carries is the decision.
    #
    # `sso_session_id` is for the authorization code grant, where the session
    # this token belongs to does not exist yet and the browser that consented
    # holds the organization access it is about to inherit.
    {expanded_scopes, sso_reauth_required} =
      Permissions.expand_and_filter_sso_scopes(
        user,
        scopes,
        Keyword.get(opts, :sso_session_id) || Keyword.get(opts, :user_session_id),
        Keyword.get(opts, :credential)
      )

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
      granted_scopes: scopes,
      expires_at: expires_at,
      grant_type: grant_type,
      grant_reference: grant_reference,
      user_id: user.id,
      client_id: client_id,
      user_session_id: Keyword.get(opts, :user_session_id),
      sso_reauth_required: sso_reauth_required
    }

    attrs =
      if Keyword.get(opts, :with_refresh_token, false) do
        # Use provided refresh_token_expires_at (e.g., from session) or calculate fresh
        refresh_expires_at =
          Keyword.get(
            opts,
            :refresh_token_expires_at,
            DateTime.add(DateTime.utc_now(), @default_refresh_token_expires_in, :second)
          )

        refresh_opts = [
          session_id: Keyword.get(opts, :user_session_id),
          expires_in: @default_refresh_token_expires_in
        ]

        {:ok, refresh_token, refresh_jti} =
          JWT.generate_refresh_token(user.username, "user", scopes, refresh_opts)

        refresh_token_hash = hash_refresh_token(refresh_token)

        Map.merge(attrs, %{
          refresh_jti: refresh_jti,
          refresh_token: refresh_token,
          refresh_token_expires_at: refresh_expires_at,
          refresh_token_hash: refresh_token_hash
        })
      else
        attrs
      end

    Token.build(attrs)
  end

  defp create_for_user_or_org(
         %Hexpm.Accounts.User{} = user,
         client_id,
         scopes,
         grant_type,
         grant_reference,
         opts
       ) do
    create_for_user(user, client_id, scopes, grant_type, grant_reference, opts)
  end

  defp create_for_user_or_org(
         %Hexpm.Accounts.Organization{} = org,
         client_id,
         scopes,
         grant_type,
         grant_reference,
         opts
       ) do
    create_for_org(org, client_id, scopes, grant_type, grant_reference, opts)
  end

  defp create_for_org(org, client_id, scopes, grant_type, grant_reference, opts) do
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    jwt_opts = [
      session_id: Keyword.get(opts, :user_session_id),
      expires_in: expires_in
    ]

    {:ok, access_token, jti} =
      JWT.generate_access_token(org.name, "org", scopes, jwt_opts)

    attrs = %{
      jti: jti,
      access_token: access_token,
      scopes: scopes,
      granted_scopes: scopes,
      expires_at: expires_at,
      grant_type: grant_type,
      grant_reference: grant_reference,
      organization_id: org.id,
      client_id: client_id,
      user_session_id: Keyword.get(opts, :user_session_id)
    }

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
  Creates a session and token for an API key.

  Unlike user tokens, API key tokens:
  - Have session lifetime matching access token lifetime (no long-lived session)
  - Do not include refresh tokens (client can exchange API key again)
  - Use the API key's user/organization for authentication
  """
  def create_session_and_token_for_api_key(
        user_or_org,
        client_id,
        scopes,
        grant_type,
        grant_reference \\ nil,
        opts \\ []
      ) do
    # For API key tokens, session expires with the access token (30 minutes)
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)
    session_expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    {user, organization} =
      case user_or_org do
        %Hexpm.Accounts.User{} = u -> {u, nil}
        %Hexpm.Accounts.Organization{} = o -> {nil, o}
      end

    max_sessions =
      if organization do
        UserSessions.get_organization_session_limit(organization)
      else
        UserSessions.max_user_sessions()
      end

    # Enforce session limit outside transaction
    UserSessions.enforce_session_limit(user_or_org, max_sessions)

    # Pre-compute JWT outside the transaction (CPU-intensive ES256 signing)
    token_opts =
      Keyword.merge(opts, expires_in: expires_in, with_refresh_token: false)

    token_changeset =
      create_for_user_or_org(
        user_or_org,
        client_id,
        scopes,
        grant_type,
        grant_reference,
        token_opts
      )

    # Build flat Multi (no nested transactions, last_use folded into INSERT)
    UserSessions.build_api_key_session_multi(user, organization, client_id, session_expires_at,
      name: Keyword.get(opts, :name),
      usage_info: Keyword.get(opts, :usage_info)
    )
    |> Ecto.Multi.run(:token, fn _repo, %{session: session} ->
      token_changeset
      |> Ecto.Changeset.put_change(:user_session_id, session.id)
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Creates a session and token for a user atomically within a transaction.

  Pass `:authorization_code` to redeem a code in the same transaction: the code
  is consumed first, so the session and token exist only if this request is the
  one that consumed it, and `{:error, :already_used}` comes back when another
  request got there first.
  """
  def create_session_and_token_for_user(
        user,
        client_id,
        scopes,
        grant_type,
        grant_reference \\ nil,
        opts \\ []
      ) do
    # Enforce session limit outside transaction
    UserSessions.enforce_session_limit(user)

    # Compute session expiration upfront (used for both session and refresh token)
    session_expires_at =
      DateTime.add(DateTime.utc_now(), UserSessions.default_session_expires_in(), :second)

    browser_session_id = Keyword.get(opts, :browser_session_id)

    # Pre-compute JWT outside the transaction (CPU-intensive ES256 signing)
    token_opts =
      opts
      |> Keyword.put(:refresh_token_expires_at, session_expires_at)
      |> Keyword.put(:sso_session_id, browser_session_id)

    token_changeset =
      create_for_user(user, client_id, scopes, grant_type, grant_reference, token_opts)

    # Build flat Multi (no nested transactions, last_use folded into INSERT)
    Keyword.get(opts, :authorization_code)
    |> consume_authorization_code_multi()
    |> Ecto.Multi.append(
      UserSessions.build_oauth_session_multi(user, client_id,
        expires_at: session_expires_at,
        name: Keyword.get(opts, :name),
        usage_info: Keyword.get(opts, :usage_info),
        audit: Keyword.fetch!(opts, :audit)
      )
    )
    |> Ecto.Multi.run(:organization_sso_sessions, fn _repo, %{session: session} ->
      {:ok, Hexpm.Accounts.SSO.grant_org_sessions!(browser_session_id, session.id, user.id)}
    end)
    |> Ecto.Multi.run(:token, fn _repo, %{session: session} ->
      token_changeset
      |> Ecto.Changeset.put_change(:user_session_id, session.id)
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, :authorization_code, reason, _changes} -> {:error, reason}
      {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
    end
  end

  defp consume_authorization_code_multi(nil), do: Ecto.Multi.new()

  defp consume_authorization_code_multi(auth_code) do
    Ecto.Multi.run(Ecto.Multi.new(), :authorization_code, fn _repo, _changes ->
      AuthorizationCodes.consume(auth_code)
    end)
  end

  @doc """
  Revokes an old token and creates a new one atomically within a transaction.
  Used for refresh token grant to ensure the old token is only revoked if the new one is created successfully.

  The old token is taken under `FOR UPDATE` and re-checked there, so of two
  refreshes presenting the same token one issues the replacement and the other
  gets `{:error, :token_revoked}` instead of a second live child. The session is
  taken next and refused if it is no longer live, which is also the order
  `UserSessions.revoke/3` takes them in.
  """
  def revoke_and_create_token(
        old_token,
        client_id,
        scopes,
        grant_type,
        grant_reference \\ nil,
        opts \\ []
      ) do
    # Pre-compute JWT outside the transaction (CPU-intensive ES256 signing)
    token_opts =
      Keyword.put(opts, :refresh_token_expires_at, old_token.refresh_token_expires_at)

    token_changeset =
      create_for_user(old_token.user, client_id, scopes, grant_type, grant_reference, token_opts)

    session_id = Keyword.get(opts, :user_session_id) || old_token.user_session_id

    Repo.transaction(fn ->
      token = locked_token(old_token.id)
      session = session_id && locked_session(session_id)

      cond do
        is_nil(token) or revoked?(token) -> Repo.rollback(:token_revoked)
        refresh_token_expired?(token) -> Repo.rollback(:token_expired)
        session && not session_live?(session) -> Repo.rollback(:session_revoked)
        true -> :ok
      end

      Repo.update!(revoke_changeset(token))

      new_token =
        token_changeset
        |> Ecto.Changeset.put_change(:user_session_id, session_id)
        |> Repo.insert()
        |> case do
          {:ok, new_token} -> new_token
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if session && Keyword.has_key?(opts, :usage_info) do
        UserSessions.update_last_use(session, Keyword.get(opts, :usage_info))
      end

      new_token
    end)
  end

  defp locked_token(id) do
    from(t in Token, where: t.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  # `FOR NO KEY UPDATE` rather than `FOR UPDATE`: it conflicts with the plain
  # update that revoking a session takes, which is what has to serialize here,
  # and leaves tokens referencing the session free to be inserted.
  defp locked_session(id) do
    from(s in UserSession, where: s.id == ^id, lock: "FOR NO KEY UPDATE")
    |> Repo.one()
  end

  defp session_live?(%UserSession{revoked_at: nil, expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  defp session_live?(%UserSession{}), do: false

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

  # The session is joined and reduced to whether it is live in the same query,
  # so a token lookup stays one round trip and one index lookup wider.
  defp find_token_by_jti(jti, type, client_id) do
    now = DateTime.utc_now()

    from(t in Token,
      left_join: s in assoc(t, :user_session),
      select: {t, is_nil(s.id) or (is_nil(s.revoked_at) and s.expires_at > ^now)}
    )
    |> filter_by_jti(type, jti)
    |> filter_by_client(client_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      {token, session_live?} -> {:ok, token, session_live?}
    end
  end

  defp filter_by_jti(query, :access, jti), do: from(t in query, where: t.jti == ^jti)
  defp filter_by_jti(query, :refresh, jti), do: from(t in query, where: t.refresh_jti == ^jti)

  defp filter_by_client(query, nil), do: query
  defp filter_by_client(query, client_id), do: from(t in query, where: t.client_id == ^client_id)

  defp maybe_validate(token, session_live?, true, :access) do
    if valid?(token) and session_live? do
      :ok
    else
      {:error, :token_invalid}
    end
  end

  defp maybe_validate(token, session_live?, true, :refresh) do
    if refresh_token_valid?(token) and session_live? do
      :ok
    else
      {:error, :token_invalid}
    end
  end

  defp maybe_validate(_token, _session_live?, false, _type), do: :ok

  defp maybe_preload(token, []), do: token
  defp maybe_preload(token, preload), do: Repo.preload(token, preload)
end

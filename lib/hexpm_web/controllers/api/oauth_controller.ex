defmodule HexpmWeb.API.OAuthController do
  use HexpmWeb, :controller

  import HexpmWeb.RequestHelpers, only: [build_usage_info: 1]

  alias Hexpm.Accounts.Organization
  alias Hexpm.{SecurityLog, UserSessions}
  alias Hexpm.OAuth.{Clients, Tokens, AuthorizationCodes, DeviceCodes}

  defp safe_param(params, key), do: safe_string(params[key])

  @doc """
  Standard OAuth 2.0 token endpoint for API access.
  Handles multiple grant types: authorization_code, device_code, refresh_token, client_credentials.
  """
  def token(conn, params) do
    case get_grant_type(params) do
      "authorization_code" ->
        handle_authorization_code_grant(conn, params)

      "urn:ietf:params:oauth:grant-type:device_code" ->
        handle_device_code_grant(conn, params)

      "refresh_token" ->
        handle_refresh_token_grant(conn, params)

      "client_credentials" ->
        handle_client_credentials_grant(conn, params)

      invalid_grant ->
        render_oauth_error(
          conn,
          :unsupported_grant_type,
          "Unsupported grant type: #{inspect(invalid_grant)}"
        )
    end
  end

  @doc """
  Device authorization endpoint for device flow.
  """
  def device_authorization(conn, params) do
    with {:ok, client} <- validate_client(safe_param(params, "client_id")),
         :ok <-
           validate_client_supports_grant(client, "urn:ietf:params:oauth:grant-type:device_code"),
         {:ok, scopes} <- validate_scopes(client, params["scope"]) do
      case DeviceCodes.initiate_device_authorization(conn, client.client_id, scopes,
             name: safe_param(params, "name")
           ) do
        {:ok, response} ->
          render(conn, :device_authorization, device_response: response)

        {:error, %Ecto.Changeset{} = changeset} ->
          render_oauth_error(conn, :invalid_request, changeset_description(changeset))
      end
    else
      {:error, error, description} ->
        render_oauth_error(conn, error, description)

      {:error, error} ->
        render_oauth_error(conn, :invalid_client, error)
    end
  end

  @doc """
  OAuth 2.0 token revocation endpoint (RFC 7009).
  """
  def revoke(conn, params) do
    case revoke_token(params) do
      :ok ->
        # RFC 7009 specifies 200 OK for successful revocation
        send_resp(conn, 200, "")

      {:error, _reason} ->
        # RFC 7009 specifies 200 OK even for invalid tokens (security)
        send_resp(conn, 200, "")
    end
  end

  @doc """
  OAuth session revocation endpoint using a refresh token hash.
  Allows revocation of the session and all its tokens when the actual token value is not available.
  """
  def revoke_by_hash(conn, params) do
    case revoke_token_by_hash(params) do
      :ok ->
        send_resp(conn, 200, "")

      {:error, _reason} ->
        # Return 200 OK even for invalid tokens (security per RFC 7009)
        send_resp(conn, 200, "")
    end
  end

  defp get_grant_type(%{"grant_type" => grant_type}), do: grant_type
  defp get_grant_type(_), do: nil

  defp handle_authorization_code_grant(conn, params) do
    with {:ok, client} <- authenticate_client(params),
         :ok <- validate_client_supports_grant(client, "authorization_code"),
         {:ok, auth_code} <-
           validate_authorization_code(safe_param(params, "code"), client.client_id),
         :ok <- validate_redirect_uri_match(auth_code, params["redirect_uri"]),
         :ok <- validate_pkce(auth_code, safe_param(params, "code_verifier")) do
      usage_info = build_usage_info(conn)
      audit = %{audit_data(conn) | user: auth_code.user}

      case Tokens.create_session_and_token_for_user(
             auth_code.user,
             client.client_id,
             auth_code.scopes,
             "authorization_code",
             "authorization_code:#{auth_code.id}",
             name: safe_param(params, "name"),
             with_refresh_token: true,
             usage_info: usage_info,
             audit: audit,
             browser_session_id: auth_code.user_session_id,
             authorization_code: auth_code
           ) do
        {:ok, token} ->
          render(conn, :token, token: token)

        {:error, :already_used} ->
          render_oauth_error(
            conn,
            :invalid_grant,
            "Authorization code expired or already used"
          )

        {:error, %Ecto.Changeset{data: %Hexpm.UserSession{}} = changeset} ->
          render_oauth_error(conn, :invalid_request, changeset_description(changeset))

        {:error, changeset} ->
          render_oauth_error(
            conn,
            :server_error,
            "Failed to create token: #{inspect(changeset.errors)}"
          )
      end
    else
      {:error, error, description} ->
        render_oauth_error(conn, error, description)
    end
  end

  defp handle_device_code_grant(conn, params) do
    with {:ok, client} <- validate_client(safe_param(params, "client_id")),
         :ok <-
           validate_client_supports_grant(client, "urn:ietf:params:oauth:grant-type:device_code") do
      usage_info = build_usage_info(conn)

      case DeviceCodes.poll_device_token(
             safe_param(params, "device_code"),
             safe_param(params, "client_id"),
             usage_info
           ) do
        {:ok, token} ->
          render(conn, :token, token: token)

        {:error, error, description} ->
          render_oauth_error(conn, error, description)
      end
    else
      {:error, error, description} ->
        render_oauth_error(conn, error, description)

      {:error, error} ->
        render_oauth_error(conn, :invalid_client, error)
    end
  end

  defp handle_refresh_token_grant(conn, params) do
    with {:ok, client} <- authenticate_client(params),
         :ok <- validate_client_supports_grant(client, "refresh_token"),
         {:ok, token} <-
           validate_refresh_token(safe_param(params, "refresh_token"), client.client_id) do
      usage_info = build_usage_info(conn)

      # Refresh from the originally granted scopes so dynamic scopes
      # ("repositories") are re-expanded against current organization
      # memberships, instead of carrying the expansion frozen at session
      # creation for the session's whole lifetime.
      case Tokens.revoke_and_create_token(
             token,
             client.client_id,
             token.granted_scopes,
             "refresh_token",
             "token:#{token.jti}",
             with_refresh_token: true,
             user_session_id: token.user_session_id,
             usage_info: usage_info
           ) do
        {:ok, new_token} ->
          render(conn, :token, token: new_token)

        {:error, :token_revoked} ->
          refresh_failure(conn, :revoked)

        {:error, :token_expired} ->
          refresh_failure(conn, :expired)

        {:error, :session_revoked} ->
          refresh_failure(conn, :session_revoked)

        {:error, %Ecto.Changeset{data: %Hexpm.UserSession{}} = changeset} ->
          render_oauth_error(conn, :invalid_request, changeset_description(changeset))

        {:error, changeset} ->
          render_oauth_error(
            conn,
            :server_error,
            "Failed to create token: #{inspect(changeset.errors)}"
          )
      end
    else
      {:error, :refresh_token, reason} ->
        refresh_failure(conn, reason)

      {:error, error, description} ->
        render_oauth_error(conn, error, description)
    end
  end

  defp refresh_failure(conn, reason) do
    SecurityLog.auth_failure(conn, :refresh_token, reason)
    render_oauth_error(conn, :invalid_grant, refresh_failure_description(reason))
  end

  defp refresh_failure_description(:revoked), do: "Refresh token has been revoked"
  defp refresh_failure_description(:expired), do: "Refresh token has expired"
  defp refresh_failure_description(:session_revoked), do: "Session has been revoked"
  defp refresh_failure_description(:invalid), do: "Invalid refresh token"

  defp handle_client_credentials_grant(conn, params) do
    with {:ok, client} <- validate_client(safe_param(params, "client_id")),
         :ok <- validate_client_supports_grant(client, "client_credentials"),
         {:ok, api_key_secret} <- validate_api_key_secret(safe_param(params, "client_secret")),
         {:ok, auth_info} <- authenticate_api_key(api_key_secret, conn),
         {:ok, scopes} <- expand_and_validate_scopes(params["scope"], auth_info) do
      usage_info = build_usage_info(conn)

      # Determine user or organization from the API key
      user_or_org = auth_info.user || auth_info.organization

      case Tokens.create_session_and_token_for_api_key(
             user_or_org,
             client.client_id,
             scopes,
             "client_credentials",
             "key:#{auth_info.auth_credential.id}",
             name: safe_param(params, "name"),
             usage_info: usage_info,
             credential: auth_info.auth_credential
           ) do
        {:ok, token} ->
          render(conn, :token, token: token)

        {:error, %Ecto.Changeset{data: %Hexpm.UserSession{}} = changeset} ->
          render_oauth_error(conn, :invalid_request, changeset_description(changeset))

        {:error, changeset} ->
          render_oauth_error(
            conn,
            :server_error,
            "Failed to create token: #{inspect(changeset.errors)}"
          )
      end
    else
      {:error, error} when is_atom(error) ->
        render_oauth_error(conn, error, error_description(error))

      {:error, error, description} ->
        render_oauth_error(conn, error, description)

      {:error, error} ->
        render_oauth_error(conn, :invalid_client, error)
    end
  end

  defp validate_client_supports_grant(client, grant_type) do
    if Clients.supports_grant_type?(client, grant_type) do
      :ok
    else
      {:error, :unauthorized_client, "Client not authorized for this grant type"}
    end
  end

  defp validate_api_key_secret(nil), do: {:error, :invalid_request}
  defp validate_api_key_secret(""), do: {:error, :invalid_request}
  defp validate_api_key_secret(secret) when is_binary(secret), do: {:ok, secret}

  defp authenticate_api_key(api_key_secret, conn) do
    usage_info = build_usage_info(conn)

    case Hexpm.Accounts.Auth.key_auth(api_key_secret, usage_info, preload: :oauth) do
      {:ok, auth_info} ->
        {:ok, auth_info}

      {:error, :invalid} ->
        SecurityLog.auth_failure(conn, :api_key, :invalid)
        {:error, :invalid_client}

      {:error, :revoked, key} ->
        SecurityLog.auth_failure(conn, :api_key, :revoked, key: key)
        {:error, :invalid_client}
    end
  end

  defp expand_and_validate_scopes(scope_string, auth_info)
       when is_binary(scope_string) or is_nil(scope_string) do
    requested_scopes = String.split(scope_string || "", " ", trim: true)

    user_or_org = auth_info.user || auth_info.organization
    api_key = auth_info.auth_credential

    # Expand scopes, constraining by API key permissions
    # The expansion itself ensures scopes don't exceed key permissions
    expanded_scopes =
      Hexpm.Permissions.expand_repositories_scope(user_or_org, requested_scopes, api_key)

    # Final validation: check that all requested scopes are allowed
    # This validates non-repository scopes (like "api")
    if validate_scopes_against_key(expanded_scopes, api_key.permissions, user_or_org) do
      {:ok, expanded_scopes}
    else
      {:error, :invalid_scope, "Requested scopes exceed API key permissions"}
    end
  end

  defp expand_and_validate_scopes(_scope_string, _auth_info) do
    {:error, :invalid_scope, "Invalid scope parameter"}
  end

  defp validate_scopes_against_key(scopes, permissions, user_or_org) do
    allowed_scopes =
      permissions
      |> Enum.flat_map(&Hexpm.Permissions.permission_to_scopes/1)
      |> MapSet.new()

    Enum.all?(scopes, fn scope ->
      scope in allowed_scopes or
        (:all_repositories in allowed_scopes and reaches_repository?(user_or_org, scope))
    end)
  end

  # The `repositories` permission means every repository this principal reaches,
  # not every repository there is, so the name has to be resolved against the
  # principal rather than matched as a prefix. The CDN edges verify
  # `repository:<org>` from the token alone, so a scope minted here is access to
  # that organization until the token expires.
  #
  # The public repository is the exception: `expand_repositories_scope/3` adds it
  # for every principal and it carries nothing private.
  defp reaches_repository?(user_or_org, "repository:" <> organization) do
    organization == Organization.hexpm(recursive: false).name or
      match?(
        {:ok, _},
        Hexpm.Permissions.verify_user_access(user_or_org, "repository", organization)
      )
  end

  defp reaches_repository?(_user_or_org, _scope), do: false

  defp error_description(:invalid_request), do: "Missing or invalid client_secret"
  defp error_description(:invalid_client), do: "Invalid API key"

  defp revoke_token(%{"token" => token_value, "client_id" => client_id})
       when is_binary(token_value) and is_binary(client_id) do
    with {:ok, _client} <- validate_client(client_id),
         {:ok, type, token} <- lookup_token_for_revocation(token_value, client_id) do
      case revoke_for_type(type, token) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, :revocation_failed}
      end
    else
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp revoke_token(_params), do: {:error, :invalid_request}

  # RFC 7009: revoking a refresh token also revokes the access tokens issued
  # from the same grant. Marking only the row presented would leave the session
  # and its organization access alive, and a sibling token would refresh
  # straight back into the same scopes.
  defp revoke_for_type(:refresh, token), do: UserSessions.revoke_for_oauth_token(token)
  defp revoke_for_type(:access, token), do: Tokens.revoke(token)

  defp revoke_token_by_hash(%{"token_hash" => token_hash})
       when is_binary(token_hash) and token_hash != "" do
    case Tokens.lookup_by_refresh_token_hash(token_hash) do
      {:ok, token} ->
        case UserSessions.revoke_for_oauth_token(token) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :revocation_failed}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp revoke_token_by_hash(_params), do: {:error, :invalid_request}

  defp lookup_token_for_revocation(token_value, client_id) do
    # Try to find as access token first
    case lookup_for_revocation(token_value, :access, client_id) do
      {:ok, token} -> {:ok, :access, token}
      {:error, _} -> lookup_refresh_token_for_revocation(token_value, client_id)
    end
  end

  defp lookup_refresh_token_for_revocation(token_value, client_id) do
    case lookup_for_revocation(token_value, :refresh, client_id) do
      {:ok, token} -> {:ok, :refresh, token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup_for_revocation(token_value, type, client_id) do
    case Tokens.lookup(token_value, type, client_id: client_id, validate: false, preload: []) do
      {:ok, token} -> {:ok, token}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp validate_client(client_id) when is_binary(client_id) and client_id != "" do
    case Clients.get(client_id) do
      nil -> {:error, "Invalid client"}
      client -> {:ok, client}
    end
  end

  defp validate_client(_), do: {:error, "Missing client_id"}

  defp authenticate_client(params) do
    with {:ok, client} <- validate_client(safe_param(params, "client_id")) do
      if Clients.requires_authentication?(client) do
        case Clients.authenticate?(client, safe_param(params, "client_secret")) do
          true -> {:ok, client}
          false -> {:error, :invalid_client, "Invalid client credentials"}
        end
      else
        {:ok, client}
      end
    else
      {:error, error} -> {:error, :invalid_client, error}
    end
  end

  defp validate_scopes(client, scope_string)
       when is_binary(scope_string) or is_nil(scope_string) do
    scopes =
      (scope_string || "")
      |> String.split(" ", trim: true)
      |> Hexpm.Permissions.expand_api_scope()

    if Clients.supports_scopes?(client, scopes) do
      {:ok, scopes}
    else
      {:error, :invalid_scope, "Invalid scope"}
    end
  end

  defp validate_scopes(_client, _scope_string), do: {:error, :invalid_scope, "Invalid scope"}

  defp validate_authorization_code(code, client_id) when is_binary(code) and code != "" do
    case AuthorizationCodes.get_by_code(code, client_id) do
      nil ->
        {:error, :invalid_grant, "Invalid authorization code"}

      auth_code ->
        if AuthorizationCodes.valid?(auth_code) do
          {:ok, Hexpm.Repo.preload(auth_code, :user)}
        else
          {:error, :invalid_grant, "Authorization code expired or already used"}
        end
    end
  end

  defp validate_authorization_code(_, _),
    do: {:error, :invalid_grant, "Missing authorization code"}

  defp validate_redirect_uri_match(auth_code, redirect_uri) do
    if auth_code.redirect_uri == redirect_uri do
      :ok
    else
      {:error, :invalid_grant, "Redirect URI mismatch"}
    end
  end

  defp validate_pkce(auth_code, code_verifier)
       when is_binary(code_verifier) and code_verifier != "" do
    if AuthorizationCodes.verify_code_challenge(auth_code, code_verifier) do
      :ok
    else
      {:error, :invalid_grant, "Invalid code verifier"}
    end
  end

  defp validate_pkce(_, _),
    do: {:error, :invalid_grant, "Missing required parameter: code_verifier"}

  defp validate_refresh_token(user_refresh_token, client_id)
       when is_binary(user_refresh_token) and user_refresh_token != "" do
    case Tokens.lookup(user_refresh_token, :refresh, client_id: client_id, validate: false) do
      {:ok, token} ->
        cond do
          Tokens.revoked?(token) -> {:error, :refresh_token, :revoked}
          Tokens.refresh_token_expired?(token) -> {:error, :refresh_token, :expired}
          true -> {:ok, token}
        end

      {:error, _} ->
        {:error, :refresh_token, :invalid}
    end
  end

  defp validate_refresh_token(_, _), do: {:error, :invalid_grant, "Missing refresh token"}

  defp changeset_description(changeset) do
    changeset
    |> translate_errors()
    |> Enum.map_join("; ", fn
      {field, message} when is_binary(message) -> "#{field} #{message}"
      {field, _message} -> "#{field} is invalid"
    end)
  end

  defp render_oauth_error(conn, error_type, description) do
    status = error_status(error_type)

    conn
    |> put_status(status)
    |> render(:error, error_type: error_type, description: description)
  end

  defp error_status(:invalid_request), do: 400
  defp error_status(:invalid_client), do: 401
  defp error_status(:invalid_grant), do: 400
  defp error_status(:unauthorized_client), do: 400
  defp error_status(:unsupported_grant_type), do: 400
  defp error_status(:invalid_scope), do: 400
  defp error_status(:access_denied), do: 403
  defp error_status(:server_error), do: 500
  defp error_status(:authorization_pending), do: 400
  defp error_status(:expired_token), do: 400
  defp error_status(_), do: 400
end

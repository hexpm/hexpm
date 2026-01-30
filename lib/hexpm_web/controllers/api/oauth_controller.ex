defmodule HexpmWeb.API.OAuthController do
  use HexpmWeb, :controller

  import HexpmWeb.RequestHelpers, only: [build_usage_info: 1]

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

        {:error, reason} ->
          render_oauth_error(
            conn,
            :server_error,
            "Failed to initiate device authorization: #{reason}"
          )
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

  defp get_grant_type(%{"grant_type" => grant_type}), do: grant_type
  defp get_grant_type(_), do: nil

  defp handle_authorization_code_grant(conn, params) do
    with {:ok, client} <- authenticate_client(params),
         :ok <- validate_client_supports_grant(client, "authorization_code"),
         {:ok, auth_code} <- validate_authorization_code(safe_param(params, "code"), client.client_id),
         :ok <- validate_redirect_uri_match(auth_code, params["redirect_uri"]),
         :ok <- validate_pkce(auth_code, safe_param(params, "code_verifier")) do
      {:ok, used_auth_code} = AuthorizationCodes.mark_as_used(auth_code)
      usage_info = build_usage_info(conn)

      case Tokens.create_session_and_token_for_user(
             used_auth_code.user,
             client.client_id,
             used_auth_code.scopes,
             "authorization_code",
             used_auth_code.code,
             name: safe_param(params, "name"),
             with_refresh_token: true,
             usage_info: usage_info,
             audit: audit_data(conn)
           ) do
        {:ok, token} ->
          render(conn, :token, token: token)

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

      case DeviceCodes.poll_device_token(safe_param(params, "device_code"), safe_param(params, "client_id"), usage_info) do
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
         {:ok, token} <- validate_refresh_token(safe_param(params, "refresh_token"), client.client_id) do
      usage_info = build_usage_info(conn)

      case Tokens.revoke_and_create_token(
             token,
             client.client_id,
             token.scopes,
             "refresh_token",
             params["refresh_token"],
             with_refresh_token: true,
             user_session_id: token.user_session_id,
             usage_info: usage_info
           ) do
        {:ok, new_token} ->
          render(conn, :token, token: new_token)

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

  defp handle_client_credentials_grant(conn, params) do
    with {:ok, client} <- validate_client(safe_param(params, "client_id")),
         :ok <- validate_client_supports_grant(client, "client_credentials"),
         {:ok, api_key_secret} <- validate_api_key_secret(safe_param(params, "client_secret")),
         {:ok, auth_info} <- authenticate_api_key(api_key_secret, conn),
         {:ok, scopes} <- expand_and_validate_scopes(params["scope"], auth_info) do
      usage_info = build_usage_info(conn)

      # Determine user or organization from the API key
      user_or_org = auth_info.user || auth_info.organization

      # Build audit data with the authenticated user/org
      audit_data = %{
        user: user_or_org,
        auth_credential: auth_info.auth_credential,
        user_agent: conn.assigns.user_agent,
        remote_ip: HexpmWeb.RequestHelpers.parse_ip(conn.remote_ip)
      }

      case Tokens.create_session_and_token_for_api_key(
             user_or_org,
             client.client_id,
             scopes,
             "client_credentials",
             api_key_secret,
             name: safe_param(params, "name"),
             usage_info: usage_info,
             audit: audit_data
           ) do
        {:ok, token} ->
          render(conn, :token, token: token)

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

    case Hexpm.Accounts.Auth.key_auth(api_key_secret, usage_info) do
      {:ok, auth_info} -> {:ok, auth_info}
      :error -> {:error, :invalid_client}
      :revoked -> {:error, :invalid_client}
    end
  end

  defp expand_and_validate_scopes(scope_string, auth_info)
       when is_binary(scope_string) or is_nil(scope_string) do
    requested_scopes = String.split(scope_string || "", " ", trim: true)

    user = auth_info.user || (auth_info.organization && auth_info.organization.user)
    api_key = auth_info.auth_credential

    # Expand scopes, constraining by API key permissions
    # The expansion itself ensures scopes don't exceed key permissions
    expanded_scopes = Hexpm.Permissions.expand_repositories_scope(user, requested_scopes, api_key)

    # Final validation: check that all requested scopes are allowed
    # This validates non-repository scopes (like "api")
    if validate_scopes_against_key(expanded_scopes, api_key.permissions) do
      {:ok, expanded_scopes}
    else
      {:error, :invalid_scope, "Requested scopes exceed API key permissions"}
    end
  end

  defp expand_and_validate_scopes(_scope_string, _auth_info) do
    {:error, :invalid_scope, "Invalid scope parameter"}
  end

  defp validate_scopes_against_key(scopes, permissions) do
    # Build set of allowed scopes from key permissions
    allowed_scopes =
      Enum.flat_map(permissions, fn permission ->
        case permission.domain do
          "api" -> ["api"]
          "repository" -> ["repository:#{permission.resource}"]
          "repositories" -> [:all_repositories]
          _ -> []
        end
      end)
      |> MapSet.new()

    # Check if all scopes are allowed
    Enum.all?(scopes, fn scope ->
      scope in allowed_scopes or
        (:all_repositories in allowed_scopes and String.starts_with?(scope, "repository:"))
    end)
  end

  defp error_description(:unauthorized_client), do: "Client not authorized for this grant type"
  defp error_description(:invalid_request), do: "Missing or invalid client_secret"
  defp error_description(:invalid_client), do: "Invalid API key"
  defp error_description(_), do: "An error occurred"

  defp revoke_token(%{"token" => token_value, "client_id" => client_id})
       when is_binary(token_value) and is_binary(client_id) do
    with {:ok, _client} <- validate_client(client_id),
         {:ok, token} <- lookup_token_for_revocation(token_value, client_id) do
      case Tokens.revoke(token) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, :revocation_failed}
      end
    else
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp revoke_token(_params), do: {:error, :invalid_request}

  defp lookup_token_for_revocation(token_value, client_id) do
    # Try to find as access token first
    case lookup_access_token_for_revocation(token_value, client_id) do
      {:ok, token} -> {:ok, token}
      {:error, _} -> lookup_refresh_token_for_revocation(token_value, client_id)
    end
  end

  defp lookup_access_token_for_revocation(user_access_token, client_id) do
    case Tokens.lookup(user_access_token, :access,
           client_id: client_id,
           validate: false,
           preload: []
         ) do
      {:ok, token} -> {:ok, token}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp lookup_refresh_token_for_revocation(user_refresh_token, client_id) do
    case Tokens.lookup(user_refresh_token, :refresh,
           client_id: client_id,
           validate: false,
           preload: []
         ) do
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

  defp validate_scopes(client, scope_string) when is_binary(scope_string) or is_nil(scope_string) do
    scopes = String.split(scope_string || "", " ", trim: true)

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

  defp validate_pkce(auth_code, code_verifier) when is_binary(code_verifier) and code_verifier != "" do
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
          Tokens.revoked?(token) ->
            {:error, :invalid_grant, "Refresh token has been revoked"}

          Tokens.refresh_token_expired?(token) ->
            {:error, :invalid_grant, "Refresh token has expired"}

          true ->
            {:ok, token}
        end

      {:error, :not_found} ->
        {:error, :invalid_grant, "Invalid refresh token"}

      {:error, :invalid_token} ->
        {:error, :invalid_grant, "Invalid refresh token"}

      {:error, _} ->
        {:error, :invalid_grant, "Invalid refresh token"}
    end
  end

  defp validate_refresh_token(_, _), do: {:error, :invalid_grant, "Missing refresh token"}

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

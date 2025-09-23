defmodule HexpmWeb.API.OAuthController do
  use HexpmWeb, :controller

  alias Hexpm.OAuth.{Clients, Sessions, Tokens, AuthorizationCodes, DeviceCodes}

  @doc """
  Standard OAuth 2.0 token endpoint for API access.
  Handles multiple grant types: authorization_code, device_code, refresh_token, token-exchange.
  """
  def token(conn, params) do
    case get_grant_type(params) do
      "authorization_code" ->
        handle_authorization_code_grant(conn, params)

      "urn:ietf:params:oauth:grant-type:device_code" ->
        handle_device_code_grant(conn, params)

      "refresh_token" ->
        handle_refresh_token_grant(conn, params)

      "urn:ietf:params:oauth:grant-type:token-exchange" ->
        handle_token_exchange_grant(conn, params)

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
    with {:ok, client} <- validate_client(params["client_id"]),
         {:ok, scopes} <- validate_scopes(client, params["scope"]) do
      case DeviceCodes.initiate_device_authorization(conn, client.client_id, scopes,
             name: params["name"]
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
         {:ok, auth_code} <- validate_authorization_code(params["code"], client.client_id),
         :ok <- validate_redirect_uri_match(auth_code, params["redirect_uri"]),
         :ok <- validate_pkce(auth_code, params["code_verifier"]) do
      # Mark code as used
      {:ok, used_auth_code} = AuthorizationCodes.mark_as_used(auth_code)

      # Create session and token
      with {:ok, session} <-
             Sessions.create_for_user(used_auth_code.user, client.client_id, name: params["name"]),
           {:ok, token} <-
             Tokens.create_and_insert_for_user(
               used_auth_code.user,
               client.client_id,
               used_auth_code.scopes,
               "authorization_code",
               used_auth_code.code,
               session_id: session.id,
               with_refresh_token: true
             ) do
        render(conn, :token, token: token)
      else
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
    case DeviceCodes.poll_device_token(params["device_code"], params["client_id"]) do
      {:ok, token} ->
        render(conn, :token, token: token)

      {:error, error, description} ->
        render_oauth_error(conn, error, description)
    end
  end

  defp handle_refresh_token_grant(conn, params) do
    with {:ok, client} <- authenticate_client(params),
         {:ok, token} <- validate_refresh_token(params["refresh_token"], client.client_id) do
      # Revoke old token
      {:ok, _} = Tokens.revoke(token)

      # Create new token in same session
      case Tokens.create_and_insert_for_user(
             token.user,
             client.client_id,
             token.scopes,
             "refresh_token",
             params["refresh_token"],
             with_refresh_token: true,
             session_id: token.session_id
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

  defp handle_token_exchange_grant(conn, params) do
    case Tokens.exchange_token(
           params["client_id"],
           params["subject_token"],
           params["subject_token_type"],
           params["scope"]
         ) do
      {:ok, token} ->
        render(conn, :token, token: token)

      {:error, error, description} ->
        render_oauth_error(conn, error, description)
    end
  end

  defp revoke_token(%{"token" => token_value, "client_id" => client_id}) do
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

  defp validate_client(nil), do: {:error, "Missing client_id"}
  defp validate_client(""), do: {:error, "Missing client_id"}

  defp validate_client(client_id) do
    case Clients.get(client_id) do
      nil -> {:error, "Invalid client"}
      client -> {:ok, client}
    end
  end

  defp authenticate_client(params) do
    with {:ok, client} <- validate_client(params["client_id"]) do
      if Clients.requires_authentication?(client) do
        case Clients.authenticate?(client, params["client_secret"]) do
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

  defp validate_scopes(client, scope_string) do
    scopes = String.split(scope_string || "", " ", trim: true)

    if Clients.supports_scopes?(client, scopes) do
      {:ok, scopes}
    else
      {:error, "Invalid scope"}
    end
  end

  defp validate_authorization_code(nil, _),
    do: {:error, :invalid_grant, "Missing authorization code"}

  defp validate_authorization_code("", _),
    do: {:error, :invalid_grant, "Missing authorization code"}

  defp validate_authorization_code(code, client_id) do
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

  defp validate_redirect_uri_match(auth_code, redirect_uri) do
    if auth_code.redirect_uri == redirect_uri do
      :ok
    else
      {:error, :invalid_grant, "Redirect URI mismatch"}
    end
  end

  defp validate_pkce(auth_code, code_verifier) do
    cond do
      is_nil(code_verifier) or code_verifier == "" ->
        {:error, :invalid_grant, "Missing required parameter: code_verifier"}

      not AuthorizationCodes.verify_code_challenge(auth_code, code_verifier) ->
        {:error, :invalid_grant, "Invalid code verifier"}

      true ->
        :ok
    end
  end

  defp validate_refresh_token(nil, _), do: {:error, :invalid_grant, "Missing refresh token"}
  defp validate_refresh_token("", _), do: {:error, :invalid_grant, "Missing refresh token"}

  defp validate_refresh_token(user_refresh_token, client_id) do
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
  defp error_status(:slow_down), do: 400
  defp error_status(:expired_token), do: 400
  defp error_status(:invalid_target), do: 400
  defp error_status(_), do: 400
end

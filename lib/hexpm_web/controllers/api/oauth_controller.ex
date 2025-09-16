defmodule HexpmWeb.API.OAuthController do
  use HexpmWeb, :controller

  alias Hexpm.Repo
  alias Hexpm.OAuth.DeviceFlow
  alias Hexpm.OAuth.{Client, Token}

  @doc """
  Standard OAuth 2.0 token endpoint for API access.
  Handles multiple grant types: authorization_code, device_code, refresh_token.
  """
  def token(conn, params) do
    case get_grant_type(params) do
      "authorization_code" ->
        handle_authorization_code_grant(conn, params)

      "urn:ietf:params:oauth:grant-type:device_code" ->
        handle_device_code_grant(conn, params)

      "refresh_token" ->
        handle_refresh_token_grant(conn, params)

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
      case DeviceFlow.initiate_device_authorization(client.client_id, scopes) do
        {:ok, response} ->
          json(conn, %{
            device_code: response.device_code,
            user_code: response.user_code,
            verification_uri: response.verification_uri,
            verification_uri_complete: response.verification_uri_complete,
            expires_in: response.expires_in,
            interval: response.interval
          })

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

  # Private functions

  defp get_grant_type(%{"grant_type" => grant_type}), do: grant_type
  defp get_grant_type(_), do: nil

  defp handle_authorization_code_grant(conn, params) do
    with {:ok, client} <- authenticate_client(params),
         {:ok, auth_code} <- validate_authorization_code(params["code"], client.client_id),
         :ok <- validate_redirect_uri_match(auth_code, params["redirect_uri"]),
         :ok <- validate_pkce(auth_code, params["code_verifier"]) do
      # Mark code as used
      {:ok, used_auth_code} = Repo.update(Hexpm.OAuth.AuthorizationCode.mark_as_used(auth_code))

      # Create token
      token_changeset =
        Token.create_for_user(
          used_auth_code.user,
          client.client_id,
          used_auth_code.scopes,
          "authorization_code",
          used_auth_code.code,
          with_refresh_token: true
        )

      case Repo.insert(token_changeset) do
        {:ok, token} ->
          json(conn, Token.to_response(token))

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
    case DeviceFlow.poll_device_token(params["device_code"], params["client_id"]) do
      {:ok, token_response} ->
        json(conn, token_response)

      {:error, error, description} ->
        render_oauth_error(conn, error, description)
    end
  end

  defp handle_refresh_token_grant(conn, params) do
    with {:ok, client} <- authenticate_client(params),
         {:ok, token} <- validate_refresh_token(params["refresh_token"], client.client_id) do
      # Revoke old token
      {:ok, _} = Repo.update(Token.revoke(token))

      # Create new token
      new_token_changeset =
        Token.create_for_user(
          token.user,
          client.client_id,
          token.scopes,
          "refresh_token",
          params["refresh_token"],
          with_refresh_token: true
        )

      case Repo.insert(new_token_changeset) do
        {:ok, new_token} ->
          json(conn, Token.to_response(new_token))

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

  defp validate_client(nil), do: {:error, "Missing client_id"}
  defp validate_client(""), do: {:error, "Missing client_id"}

  defp validate_client(client_id) do
    case Repo.get_by(Client, client_id: client_id) do
      nil -> {:error, "Invalid client"}
      client -> {:ok, client}
    end
  end

  defp authenticate_client(params) do
    with {:ok, client} <- validate_client(params["client_id"]) do
      if Client.requires_authentication?(client) do
        case Client.authenticate(client, params["client_secret"]) do
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

  defp validate_scopes(_client, nil), do: {:ok, ["api"]}
  defp validate_scopes(_client, ""), do: {:ok, ["api"]}

  defp validate_scopes(client, scope_string) do
    scopes = String.split(scope_string, " ", trim: true)

    if Client.supports_scopes?(client, scopes) do
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
    case Repo.get_by(Hexpm.OAuth.AuthorizationCode, code: code, client_id: client_id) do
      nil ->
        {:error, :invalid_grant, "Invalid authorization code"}

      auth_code ->
        if Hexpm.OAuth.AuthorizationCode.valid?(auth_code) do
          {:ok, Repo.preload(auth_code, :user)}
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

      not Hexpm.OAuth.AuthorizationCode.verify_code_challenge(auth_code, code_verifier) ->
        {:error, :invalid_grant, "Invalid code verifier"}

      true ->
        :ok
    end
  end

  defp validate_refresh_token(nil, _), do: {:error, :invalid_grant, "Missing refresh token"}
  defp validate_refresh_token("", _), do: {:error, :invalid_grant, "Missing refresh token"}

  defp validate_refresh_token(user_refresh_token, client_id) do
    # Use secure comparison like oauth_token_auth
    app_secret = Application.get_env(:hexpm, :secret)

    <<first::binary-size(32), second::binary-size(32)>> =
      :crypto.mac(:hmac, :sha256, app_secret, user_refresh_token)
      |> Base.encode16(case: :lower)

    case Repo.get_by(Token, refresh_token_first: first, client_id: client_id) do
      nil ->
        {:error, :invalid_grant, "Invalid refresh token"}

      token ->
        if Hexpm.Utils.secure_check(token.refresh_token_second, second) && Token.valid?(token) do
          {:ok, Repo.preload(token, :user)}
        else
          {:error, :invalid_grant, "Refresh token expired or revoked"}
        end
    end
  end

  defp render_oauth_error(conn, error_type, description) do
    status = error_status(error_type)

    conn
    |> put_status(status)
    |> json(%{
      error: to_string(error_type),
      error_description: description
    })
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
  defp error_status(_), do: 400
end

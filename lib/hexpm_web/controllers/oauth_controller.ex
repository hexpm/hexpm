defmodule HexpmWeb.OAuthController do
  use HexpmWeb, :controller

  alias Hexpm.Repo
  alias Hexpm.OAuth.{Client, AuthorizationCode}

  @doc """
  Standard OAuth 2.0 authorization endpoint.
  Initiates the authorization code flow.
  """
  def authorize(conn, params) do
    with {:ok, client} <- validate_client(params["client_id"]),
         {:ok, redirect_uri} <- validate_redirect_uri(client, params["redirect_uri"]),
         {:ok, scopes} <- validate_scopes(client, params["scope"]) do
      if conn.assigns.current_user do
        # User is logged in, show authorization form
        render(conn, "authorize.html", %{
          client: client,
          redirect_uri: redirect_uri,
          scopes: scopes,
          state: params["state"],
          code_challenge: params["code_challenge"],
          code_challenge_method: params["code_challenge_method"]
        })
      else
        # Redirect to login with return path
        return_path = request_url(conn) |> URI.encode_www_form()
        redirect(conn, to: ~p"/login?return=#{return_path}")
      end
    else
      {:error, error} ->
        case params["redirect_uri"] do
          nil ->
            render_oauth_error(conn, :invalid_request, "Invalid request: #{error}")

          redirect_uri ->
            error_params = %{
              error: "invalid_request",
              error_description: error,
              state: params["state"]
            }

            redirect_to_client(conn, redirect_uri, error_params)
        end
    end
  end

  @doc """
  Handles user consent for authorization.
  """
  def consent(conn, params) do
    if user = conn.assigns.current_user do
      case params["action"] do
        "approve" ->
          handle_authorization_approval(conn, user, params)

        "deny" ->
          handle_authorization_denial(conn, params)

        _ ->
          render_oauth_error(conn, :invalid_request, "Invalid action")
      end
    else
      render_oauth_error(conn, :access_denied, "User not authenticated")
    end
  end

  # Private functions

  defp handle_authorization_approval(conn, user, params) do
    with {:ok, client} <- validate_client(params["client_id"]),
         {:ok, redirect_uri} <- validate_redirect_uri(client, params["redirect_uri"]),
         {:ok, scopes} <- validate_scopes(client, params["scope"]) do
      auth_code_changeset =
        AuthorizationCode.create_for_user(
          user,
          client.client_id,
          redirect_uri,
          scopes,
          code_challenge: params["code_challenge"],
          code_challenge_method: params["code_challenge_method"]
        )

      case Repo.insert(auth_code_changeset) do
        {:ok, auth_code} ->
          success_params = %{
            code: auth_code.code,
            state: params["state"]
          }

          redirect_to_client(conn, redirect_uri, success_params)

        {:error, changeset} ->
          render_oauth_error(
            conn,
            :server_error,
            "Failed to create authorization code: #{inspect(changeset.errors)}"
          )
      end
    else
      {:error, error} ->
        error_params = %{
          error: "invalid_request",
          error_description: error,
          state: params["state"]
        }

        redirect_to_client(conn, params["redirect_uri"], error_params)
    end
  end

  defp handle_authorization_denial(conn, params) do
    error_params = %{
      error: "access_denied",
      error_description: "User denied authorization",
      state: params["state"]
    }

    redirect_to_client(conn, params["redirect_uri"], error_params)
  end

  defp validate_client(nil), do: {:error, "Missing client_id"}
  defp validate_client(""), do: {:error, "Missing client_id"}

  defp validate_client(client_id) do
    case Repo.get_by(Client, client_id: client_id) do
      nil -> {:error, "Invalid client"}
      client -> {:ok, client}
    end
  end

  defp validate_redirect_uri(client, redirect_uri) do
    if Client.valid_redirect_uri?(client, redirect_uri) do
      {:ok, redirect_uri}
    else
      {:error, "Invalid redirect_uri"}
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

  defp redirect_to_client(conn, redirect_uri, params) do
    uri = URI.parse(redirect_uri)
    query_params = URI.encode_query(params)

    redirect_url =
      case uri.query do
        nil -> "#{redirect_uri}?#{query_params}"
        _existing_query -> "#{redirect_uri}&#{query_params}"
      end

    redirect(conn, external: redirect_url)
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

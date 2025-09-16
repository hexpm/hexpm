defmodule HexpmWeb.API.AuthController do
  use HexpmWeb, :controller

  plug :required_params, ["domain"]
  plug :authorize, authentication: :required

  def show(conn, %{"domain" => domain} = params) do
    auth_credential = conn.assigns.auth_credential
    user_or_organization = conn.assigns.current_user || conn.assigns.current_organization
    resource = params["resource"]

    # Two-level permission check:
    # 1. API-level: Check if the API key/OAuth token has the required scopes/permissions
    has_api_permission =
      if auth_credential do
        Hexpm.Permissions.verify_access?(auth_credential, domain, resource)
      else
        false
      end

    if has_api_permission do
      # 2. User-level: Check if the authenticated user/organization actually owns/has access to the resource
      case Hexpm.Permissions.verify_user_access(user_or_organization, domain, resource) do
        {:ok, nil} ->
          send_resp(conn, 204, "")

        {:ok, repository} ->
          case organization_billing_active(repository, user_or_organization) do
            :ok -> send_resp(conn, 204, "")
            error -> error(conn, error)
          end

        :error ->
          error(conn, {:error, :auth})
      end
    else
      error(conn, {:error, :domain})
    end
  end
end

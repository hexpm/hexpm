defmodule HexpmWeb.API.AuthController do
  use HexpmWeb, :controller

  plug :required_params, ["domain"]
  plug :authorize, authentication: :required

  def show(conn, %{"domain" => domain} = params) do
    key = conn.assigns.key
    user_or_organization = conn.assigns.current_user || conn.assigns.current_organization
    resource = params["resource"]

    if Key.verify_permissions?(key, domain, resource) do
      case KeyPermission.verify_permissions(user_or_organization, domain, resource) do
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

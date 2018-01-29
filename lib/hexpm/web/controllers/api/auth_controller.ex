defmodule Hexpm.Web.API.AuthController do
  use Hexpm.Web, :controller

  plug :required_params, ["domain"]
  plug :authorize

  def show(conn, %{"domain" => domain} = params) do
    key = conn.assigns.key
    user = conn.assigns.current_user
    resource = params["resource"]

    cond do
      not Key.valid_permission_request?(domain, resource) ->
        render_error(conn, 400, message: "invalid permissions")

      not Key.verify_permissions?(key, domain, resource) ->
        error(conn, {:error, :domain})

      not User.verify_permissions?(user, domain, resource) ->
        error(conn, {:error, :auth})

      true ->
        send_resp(conn, 204, "")
    end
  end
end

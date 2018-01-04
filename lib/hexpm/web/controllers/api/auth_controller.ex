defmodule Hexpm.Web.API.AuthController do
  use Hexpm.Web, :controller

  plug :required_params, ["domain"]
  plug :authorize

  def show(conn, %{"domain" => domain} = params) do
    key = conn.assigns.key
    user = conn.assigns.current_user
    resource = params["resource"]

    if Key.verify_permissions?(key, domain, resource) do
      case User.verify_permissions(user, domain, resource) do
        {:ok, nil} ->
          send_resp(conn, 204, "")
        {:ok, _repository} ->
          # TODO: Change when billing is required
          # if repository.public or repository.billing_active do
          #   :ok
          # else
          #   {:error, :auth, "repository has no active billing subscription"}
          # end
          send_resp(conn, 204, "")
        :error ->
          error(conn, {:error, :auth})
      end
    else
      error(conn, {:error, :domain})
    end
  end
end

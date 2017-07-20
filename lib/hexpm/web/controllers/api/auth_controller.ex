defmodule Hexpm.Web.API.AuthController do
  use Hexpm.Web, :controller

  plug :required_params, ["domain"]
  plug :authorize

  def show(conn, %{"domain" => domain} = params) do
    key = conn.assigns.key
    user = conn.assigns.user
    resource = params["resource"]

    if domain do
      domain = domain_to_atom(domain)
      if Key.verify_permissions?(key, domain, resource) and verify?(user, domain, resource) do
        send_resp(conn, 204, "")
      else
        send_resp(conn, 403, "")
      end
    else
      send_resp(conn, 204, "")
    end
  end

  defp verify?(_user, :api, _repository) do
    true
  end
  defp verify?(user, :repository, name) do
    if repository = Repositories.get(name) do
      Repositories.access?(repository, user)
    else
      false
    end
  end
  defp verify?(_user, _domain, _repository) do
    false
  end

  defp domain_to_atom("api"), do: :api
  defp domain_to_atom("repository"), do: :repository
  defp domain_to_atom(_other), do: nil
end

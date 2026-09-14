defmodule HexpmWeb.OrganizationAuthController do
  use HexpmWeb, :controller
  alias Hexpm.Accounts.OrganizationAuth

  plug :requires_login

  def authenticate(conn, %{"organization" => name} = params) do
    user = conn.assigns.current_user
    organization = Organizations.get(name)
    return_to = safe_return_path(params["return"]) || ~p"/dashboard/orgs/#{name}"

    if organization && Organizations.get_role(organization, user) do
      case OrganizationAuth.required(user, [name], conn.assigns.current_session.id) do
        [] ->
          redirect(conn, to: return_to)

        [%{requirements: requirements}] ->
          if "tfa" in requirements do
            conn
            |> put_session(
              :tfa_return_to,
              ~p"/organizations/#{name}/authenticate?#{[return: return_to]}"
            )
            |> redirect(to: ~p"/dashboard/security")
          else
            redirect(conn, to: ~p"/sso/org/#{name}?#{[return: return_to]}")
          end
      end
    else
      not_found(conn)
    end
  end
end

defmodule HexpmWeb.API.UserController do
  use HexpmWeb, :controller

  alias HexpmWeb.SSOEnforcement

  plug :authorize,
       [authentication: :required, domains: [{"api", "read"}]]
       when action in [:test, :me, :audit_logs]

  def me(conn, _params) do
    if user = conn.assigns.current_user do
      accessible_packages =
        Packages.accessible_user_owned_packages(
          user,
          SSOEnforcement.reachable_organizations(conn)
        )

      user = %{user | owned_packages: accessible_packages}

      when_stale(conn, user, fn conn ->
        conn
        |> api_cache(:private)
        |> render(:me, user: user)
      end)
    else
      not_found(conn)
    end
  end

  def audit_logs(conn, params) do
    if user = conn.assigns.current_user do
      audit_logs = AuditLogs.all_by(user, Hexpm.Utils.safe_int(params["page"]), 100)

      render(conn, :audit_logs, audit_logs: audit_logs)
    else
      not_found(conn)
    end
  end

  def show(conn, %{"name" => name}) do
    user = Users.public_get(name, [:emails, owned_packages: :repository])

    if user && User.public_profile?(user) do
      accessible_packages =
        Packages.accessible_user_owned_packages(
          user,
          SSOEnforcement.reachable_organizations(conn)
        )

      user = %{user | owned_packages: accessible_packages}

      when_stale(conn, user, fn conn ->
        conn
        |> api_cache(:private)
        |> render(:show, user: user)
      end)
    else
      not_found(conn)
    end
  end

  def test(conn, params) do
    show(conn, params)
  end
end

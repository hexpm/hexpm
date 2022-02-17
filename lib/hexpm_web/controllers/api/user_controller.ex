defmodule HexpmWeb.API.UserController do
  use HexpmWeb, :controller

  plug :authorize,
       [authentication: :required, domain: "api", resource: "read"]
       when action in [:test, :me, :audit_logs]

  def create(conn, params) do
    params = email_param(params)

    case Users.add(params, audit: audit_data(conn)) do
      {:ok, user} ->
        location = Routes.api_user_url(conn, :show, user.username)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:private)
        |> put_status(201)
        |> render(:show, user: user)

      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  def me(conn, _params) do
    if user = conn.assigns.current_user do
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
    accessible_packages = Packages.accessible_user_owned_packages(user, conn.assigns.current_user)

    user = user && %{user | owned_packages: accessible_packages}

    if user do
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

  def reset(conn, %{"name" => name}) do
    Users.password_reset_init(name, audit: audit_data(conn))

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end

  defp email_param(params) do
    if email = params["email"] do
      Map.put_new(params, "emails", [%{"email" => email}])
    else
      params
    end
  end
end

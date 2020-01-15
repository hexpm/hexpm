defmodule HexpmWeb.Dashboard.AuditLogController do
  use HexpmWeb, :controller

  plug :requires_login

  @per_page 100

  def index(conn, params) do
    page = Hexpm.Utils.safe_int(params["page"]) || 1
    audit_logs = Hexpm.Accounts.AuditLogs.all_by(conn.assigns.current_user, page, @per_page)
    count = Hexpm.Accounts.AuditLogs.count_by(conn.assigns.current_user)

    conn
    |> render(
      "index.html",
      title: "Dashboard - Recent activities",
      container: "container page dashboard",
      audit_logs: audit_logs,
      page: page,
      per_page: @per_page,
      total_count: count
    )
  end
end

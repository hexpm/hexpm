defmodule HexpmWeb.Dashboard.AuditLogControllerTest do
  use HexpmWeb.ConnCase, async: true

  describe "GET /dashboard/audit_logs" do
    test "requires login" do
      conn = get(build_conn(), "/dashboard/audit_logs")
      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Faudit_logs"
    end

    test "shows page successfully after login" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/audit_logs")

      assert html_response(conn, :ok) =~ "Recent activities"
    end
  end
end

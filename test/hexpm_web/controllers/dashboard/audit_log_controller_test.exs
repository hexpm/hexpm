defmodule HexpmWeb.Dashboard.AuditLogControllerTest do
  use HexpmWeb.ConnCase, async: true

  describe "GET /dashboard/audit_logs" do
    test "requires login" do
      conn = get(build_conn(), "/dashboard/audit_logs")
      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Faudit_logs"
    end
  end
end

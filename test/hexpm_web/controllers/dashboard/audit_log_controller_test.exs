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

    test "shows the most recent audit logs for current user" do
      user = insert(:user)

      insert(:audit_log, user: user, action: "docs.publish")

      response =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/audit_logs")
        |> html_response(:ok)

      assert response =~ "Publish doc"
    end

    test "shows the second page of audit logs for current user" do
      user = insert(:user)

      insert(:audit_log, user: user, action: "user.create")
      insert_list(100, :audit_log, action: "user.update", user: user)

      response =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/audit_logs?page=2")
        |> html_response(:ok)

      assert response =~ "Create user"
    end
  end
end

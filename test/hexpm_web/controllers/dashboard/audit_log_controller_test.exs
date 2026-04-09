defmodule HexpmWeb.Dashboard.AuditLogControllerTest do
  use HexpmWeb.ConnCase, async: true

  describe "GET /dashboard/audit-logs" do
    test "requires login" do
      conn = get(build_conn(), "/dashboard/audit-logs")
      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Faudit-logs"
    end

    test "shows page successfully after login" do
      user = insert(:user)

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/audit-logs")

      assert html_response(conn, :ok) =~ "Recent Activities"
    end

    test "shows the most recent audit logs for current user" do
      user = insert(:user)

      insert(:audit_log,
        user: user,
        action: "docs.publish",
        params: %{
          "package" => %{"name" => "my_package"},
          "release" => %{"version" => "1.0.0"}
        }
      )

      response =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/audit-logs")
        |> html_response(:ok)

      assert response =~ "Published documentation for my_package"
    end

    test "renders page gracefully when audit log params are incomplete" do
      user = insert(:user)

      insert(:audit_log,
        user: user,
        action: "session.create",
        params: %{"type" => "oauth"}
      )

      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/audit-logs")

      assert html_response(conn, :ok) =~ "Recent Activities"
    end

    test "shows the second page of audit logs for current user" do
      user = insert(:user)

      insert(:audit_log, user: user, action: "user.create")
      insert_list(20, :audit_log, action: "user.update", user: user)

      response =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/audit-logs?page=2")
        |> html_response(:ok)

      assert response =~ "Created user account"
    end
  end
end

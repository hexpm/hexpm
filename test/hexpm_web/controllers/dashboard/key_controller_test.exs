defmodule HexpmWeb.Dashboard.KeyControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    %{
      user: insert(:user)
    }
  end

  describe "GET /dashboard/keys" do
    test "show keys", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("dashboard/keys")

      assert response(conn, 200) =~ "Keys"
    end

    test "requires login" do
      conn = get(build_conn(), "dashboard/keys")
      assert redirected_to(conn) == "/login?return=dashboard%2Fkeys"
    end
  end

  describe "POST /dashboard/keys" do
    test "generate a new key", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("dashboard/keys", %{key: %{name: "computer"}})

      assert redirected_to(conn) == "/dashboard/keys"
      assert get_flash(conn, :info) =~ "The key computer was successfully generated"
    end
  end

  describe "DELETE /dashboard/keys" do
    test "revoke key", c do
      insert(:key, user: c.user, name: "computer")

      conn =
        build_conn()
        |> test_login(c.user)
        |> delete("dashboard/keys", %{name: "computer"})

      assert redirected_to(conn) == "/dashboard/keys"
      assert get_flash(conn, :info) =~ "The key computer was revoked successfully"
    end

    test "revoking an already revoked key throws an error", c do
      insert(:key, user: c.user, name: "computer", revoked_at: ~N"2017-01-01 00:00:00")

      conn =
        build_conn()
        |> test_login(c.user)
        |> delete("dashboard/keys", %{name: "computer"})

      assert response(conn, 400) =~ "The key computer was not found"
    end
  end
end

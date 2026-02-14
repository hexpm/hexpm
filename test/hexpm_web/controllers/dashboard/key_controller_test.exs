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
        |> get("/dashboard/keys")

      assert response(conn, 200) =~ "Keys"
    end

    test "requires login" do
      conn = get(build_conn(), "/dashboard/keys")
      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Fkeys"
    end
  end

  describe "POST /dashboard/keys" do
    test "generate a new key", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{key: %{name: "computer"}})

      assert redirected_to(conn) == "/dashboard/keys"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "The key computer was successfully generated"
    end

    test "stores generated key in session and displays it once", c do
      # Create a key
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{key: %{name: "mykey"}})

      assert redirected_to(conn) == "/dashboard/keys"

      # Follow the redirect - should display the generated key
      conn = get(conn, "/dashboard/keys")
      response_body = html_response(conn, 200)

      # Modal should be present with the key
      assert response_body =~ "Key Generated Successfully"
      assert response_body =~ "mykey"

      # Key should now be removed from session
      assert get_session(conn, :generated_key) == nil

      # Reload the page - modal should not appear again
      conn = get(conn, "/dashboard/keys")
      response_body = html_response(conn, 200)

      # Modal should not be present anymore
      refute response_body =~ "Key Generated Successfully"
    end
  end

  describe "DELETE /dashboard/keys" do
    test "revoke key", c do
      insert(:key, user: c.user, name: "computer")

      conn =
        build_conn()
        |> test_login(c.user)
        |> delete("/dashboard/keys", %{name: "computer"})

      assert redirected_to(conn) == "/dashboard/keys"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "The key computer was revoked successfully"
    end

    test "revoking an already revoked key throws an error", c do
      insert(:key, user: c.user, name: "computer", revoke_at: ~N"2017-01-01 00:00:00")

      conn =
        build_conn()
        |> test_login(c.user)
        |> delete("/dashboard/keys", %{name: "computer"})

      assert response(conn, 400) =~ "The key computer was not found"
    end
  end
end

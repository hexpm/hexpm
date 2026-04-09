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

    test "redirects to sudo when not in sudo mode", c do
      conn =
        build_conn()
        |> test_login(c.user, sudo: false)
        |> get("/dashboard/keys")

      assert redirected_to(conn) == "/sudo"
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
        |> post("/dashboard/keys", %{key: %{name: "computer", expires_in: "30"}})

      assert redirected_to(conn) == "/dashboard/keys"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "The key computer was successfully generated"
    end

    test "shows validation errors when name is missing", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{key: %{name: "", expires_in: "30"}})

      response_body = response(conn, 400)
      assert response_body =~ "Generate New Key"
      assert response_body =~ "can&#39;t be blank"
    end

    test "stores generated key in session and displays it once", c do
      # Create a key
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{key: %{name: "mykey", expires_in: "30"}})

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

  describe "POST /dashboard/keys with expiry" do
    test "create key with expires_in sets revoke_at", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{key: %{name: "temp-key", expires_in: "30"}})

      assert redirected_to(conn) == "/dashboard/keys"

      key = Hexpm.Repo.one!(Hexpm.Accounts.Key.get(c.user, "temp-key"))
      assert key.revoke_at != nil

      # revoke_at should be approximately 30 days from now
      diff = DateTime.diff(key.revoke_at, DateTime.utc_now(), :day)
      assert diff >= 29 and diff <= 30
    end

    test "create key with expires_in none leaves revoke_at nil", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{key: %{name: "perm-key", expires_in: "none"}})

      assert redirected_to(conn) == "/dashboard/keys"

      key = Hexpm.Repo.one!(Hexpm.Accounts.Key.get(c.user, "perm-key"))
      assert key.revoke_at == nil
    end

    test "create key with custom expiry date sets revoke_at", c do
      future_date = Date.utc_today() |> Date.add(45)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{
          key: %{
            name: "custom-key",
            expires_in: "custom",
            custom_expiry_date: Date.to_iso8601(future_date)
          }
        })

      assert redirected_to(conn) == "/dashboard/keys"

      key = Hexpm.Repo.one!(Hexpm.Accounts.Key.get(c.user, "custom-key"))
      assert DateTime.to_date(key.revoke_at) == future_date
      assert key.revoke_at.hour == 23
      assert key.revoke_at.minute == 59
      assert key.revoke_at.second == 59
    end

    test "create key with custom expiry date in the past fails", c do
      past_date = Date.utc_today() |> Date.add(-5) |> Date.to_iso8601()

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{
          key: %{name: "bad-key", expires_in: "custom", custom_expiry_date: past_date}
        })

      assert response(conn, 400)
    end

    test "keys index shows expiry date for keys with revoke_at", c do
      revoke_at = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      insert(:key, user: c.user, name: "expiring", revoke_at: revoke_at)

      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/keys")

      body = html_response(conn, 200)
      assert body =~ "Expires"
      assert body =~ Calendar.strftime(revoke_at, "%b %d, %Y")
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

defmodule HexpmWeb.Dashboard.KeyControllerTest do
  use HexpmWeb.ConnCase, async: true
  import Swoosh.TestAssertions

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

    test "sorts keys and packages by name", c do
      insert(:package,
        name: "zulu_package",
        package_owners: [build(:package_owner, user: c.user)]
      )

      insert(:package,
        name: "alpha_package",
        package_owners: [build(:package_owner, user: c.user)]
      )

      insert(:key, user: c.user, name: "zulu_key")
      insert(:key, user: c.user, name: "alpha_key")

      document =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/keys")
        |> html_response(200)
        |> LazyHTML.from_document()

      key_names =
        document
        |> LazyHTML.query("table tbody tr td:first-child span")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      package_inputs =
        document
        |> LazyHTML.query(~s(#generate-key-modal input[name^="key[permissions][package]"]))
        |> Enum.map(&(LazyHTML.attribute(&1, "name") |> List.first()))

      assert key_names == ["alpha_key", "zulu_key"]

      assert package_inputs == [
               "key[permissions][package][alpha_package]",
               "key[permissions][package][zulu_package]"
             ]
    end

    test "shows revoke all keys only when there are keys", c do
      body =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/keys")
        |> html_response(200)

      refute body =~ "revoke-all-keys-button"
      refute body =~ "revoke-all-keys-modal"

      insert(:key, user: c.user, name: "computer")
      insert(:key, user: c.user, name: "laptop")

      document =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/keys")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert LazyHTML.query(document, "#revoke-all-keys-button") |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#revoke-all-keys-modal")
             |> LazyHTML.text()
             |> String.replace(~r/\s+/, " ") =~ "2 keys will be revoked"

      assert document
             |> LazyHTML.query(~s(#revoke-all-keys-modal form))
             |> LazyHTML.attribute("action") == ["/dashboard/keys/all"]
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

    test "generating a key sends security notification", c do
      build_conn()
      |> test_login(c.user)
      |> post("/dashboard/keys", %{key: %{name: "notify-test", expires_in: "30"}})

      user = Hexpm.Repo.preload(c.user, :emails)
      key = Hexpm.Accounts.Keys.get(user, "notify-test")

      assert_email_sent(Hexpm.Emails.api_key_created(user, key))
    end

    test "cannot generate key with repository permissions", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{
          key: %{name: "repo-key", expires_in: "30", permissions: %{"repositories" => "on"}}
        })

      assert response(conn, 400)
      refute Hexpm.Repo.one(Hexpm.Accounts.Key.get(c.user, "repo-key"))
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
      earliest_revoke_at =
        DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/keys", %{key: %{name: "temp-key", expires_in: "30"}})

      assert redirected_to(conn) == "/dashboard/keys"

      key = Hexpm.Repo.one!(Hexpm.Accounts.Key.get(c.user, "temp-key"))
      assert key.revoke_at != nil

      latest_revoke_at =
        DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

      assert DateTime.compare(key.revoke_at, earliest_revoke_at) in [:eq, :gt]
      assert DateTime.compare(key.revoke_at, latest_revoke_at) in [:eq, :lt]
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

    test "revoking a key sends security notification", c do
      {:ok, %{key: key}} =
        Hexpm.Accounts.Keys.create(c.user, %{"name" => "to-revoke", "permissions" => []},
          audit: audit_data(c.user)
        )

      build_conn()
      |> test_login(c.user)
      |> delete("/dashboard/keys", %{"name" => key.name})

      user = Hexpm.Repo.preload(c.user, :emails)
      assert_email_sent(Hexpm.Emails.api_key_revoked(user, key))
    end
  end

  describe "DELETE /dashboard/keys/all" do
    test "revokes all of the user's keys", c do
      key_a = insert(:key, user: c.user, name: "computer")
      key_b = insert(:key, user: c.user, name: "laptop")
      other_key = insert(:key, user: insert(:user), name: "computer")

      conn =
        build_conn()
        |> test_login(c.user)
        |> delete("/dashboard/keys/all")

      assert redirected_to(conn) == "/dashboard/keys"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "All keys were revoked successfully."

      assert Hexpm.Accounts.Key.revoked?(Repo.get!(Hexpm.Accounts.Key, key_a.id))
      assert Hexpm.Accounts.Key.revoked?(Repo.get!(Hexpm.Accounts.Key, key_b.id))
      refute Hexpm.Accounts.Key.revoked?(Repo.get!(Hexpm.Accounts.Key, other_key.id))

      logged =
        from(a in Hexpm.Accounts.AuditLog,
          where: a.action == "key.remove",
          select: {a.user_id, a.params["name"]}
        )
        |> Repo.all()
        |> Enum.sort()

      assert logged == [{c.user.id, "computer"}, {c.user.id, "laptop"}]

      user = Repo.preload(c.user, :emails)
      assert_email_sent(Hexpm.Emails.api_keys_all_revoked(user))
    end

    test "submits from the keys page form after sudo expires", c do
      key = insert(:key, user: c.user, name: "computer")

      [token] =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/keys")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query(~s(#revoke-all-keys-modal input[name="_sudo_token"]))
        |> LazyHTML.attribute("value")

      conn =
        build_conn()
        |> test_login(c.user, sudo: false)
        |> delete("/dashboard/keys/all", %{"_sudo_token" => token})

      assert redirected_to(conn) == "/dashboard/keys"
      assert Hexpm.Accounts.Key.revoked?(Repo.get!(Hexpm.Accounts.Key, key.id))
    end

    test "redirects to sudo when not in sudo mode", c do
      key = insert(:key, user: c.user, name: "computer")

      conn =
        build_conn()
        |> test_login(c.user, sudo: false)
        |> delete("/dashboard/keys/all")

      assert redirected_to(conn) == "/sudo"
      refute Hexpm.Accounts.Key.revoked?(Repo.get!(Hexpm.Accounts.Key, key.id))
    end
  end
end

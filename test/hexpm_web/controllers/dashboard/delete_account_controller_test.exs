defmodule HexpmWeb.Dashboard.DeleteAccountControllerTest do
  use HexpmWeb.ConnCase, async: true
  import Swoosh.TestAssertions

  alias Hexpm.Accounts.{AccountDeletionRequest, User, Users}

  setup do
    %{user: insert(:user)}
  end

  defp request_deletion(user) do
    :ok = Users.delete_request(user, audit: audit_data(user))
    Repo.get_by!(AccountDeletionRequest, user_id: user.id)
  end

  describe "GET /dashboard/delete-account" do
    test "renders warnings for sole-owned packages", c do
      package = insert(:package, package_owners: [build(:package_owner, user: c.user)])

      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/delete-account")

      assert response(conn, 200) =~ "Delete account"
      assert response(conn, 200) =~ package.name
    end

    test "renders blockers for last org admin", c do
      organization = insert(:organization)
      insert(:organization_user, user: c.user, organization: organization, role: "admin")

      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/delete-account")

      assert response(conn, 200) =~ organization.name
      refute response(conn, 200) =~ "Request account deletion"
    end

    test "requires login" do
      conn = get(build_conn(), "/dashboard/delete-account")
      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Fdelete-account"
    end

    test "redirects to /sudo without sudo", c do
      conn =
        build_conn()
        |> test_login(c.user, sudo: false)
        |> get("/dashboard/delete-account")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "redirects to /sudo when sudo is active but stale (forced freshness)", c do
      conn =
        build_conn()
        |> test_login(c.user, sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -10, :minute))
        |> get("/dashboard/delete-account")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "confirm page also redirects to /sudo without fresh sudo", c do
      conn =
        build_conn()
        |> test_login(c.user, sudo: false)
        |> get("/dashboard/delete-account/confirm", %{"key" => "anything"})

      assert redirected_to(conn) =~ "/sudo"
    end
  end

  describe "POST /dashboard/delete-account" do
    test "creates a request and sends the email", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/delete-account", %{"username" => c.user.username})

      assert redirected_to(conn) == "/dashboard/delete-account"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "confirmation link"
      assert Repo.get_by(AccountDeletionRequest, user_id: c.user.id)
      assert_email_sent(subject: "Hex.pm - Account deletion request")
    end

    test "rejects a wrong typed username", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/delete-account", %{"username" => "someone-else"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "does not match"
      refute Repo.get_by(AccountDeletionRequest, user_id: c.user.id)
    end

    test "is throttled per user", c do
      conn = build_conn() |> test_login(c.user)

      for _ <- 1..3 do
        post(conn, "/dashboard/delete-account", %{"username" => c.user.username})
      end

      conn = post(conn, "/dashboard/delete-account", %{"username" => c.user.username})
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many"
    end

    test "blocked for last org admin", c do
      organization = insert(:organization)
      insert(:organization_user, user: c.user, organization: organization, role: "admin")

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/delete-account", %{"username" => c.user.username})

      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      refute Repo.get_by(AccountDeletionRequest, user_id: c.user.id)
    end

    test "a signed _sudo_token keeps the form working after the freshness window", c do
      token =
        HexpmWeb.Plugs.Sudo.generate_form_token(c.user.id, "POST", "/dashboard/delete-account")

      conn =
        build_conn()
        |> test_login(c.user, sudo_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -10, :minute))
        |> post("/dashboard/delete-account", %{
          "username" => c.user.username,
          "_sudo_token" => token
        })

      assert redirected_to(conn) == "/dashboard/delete-account"
      assert Repo.get_by(AccountDeletionRequest, user_id: c.user.id)
    end
  end

  describe "GET /dashboard/delete-account/confirm" do
    test "renders the final confirmation page with a valid key", c do
      request = request_deletion(c.user)

      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/delete-account/confirm", %{"key" => request.key})

      assert response(conn, 200) =~ "Delete my account"
    end

    test "rejects an invalid key with a generic error", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/delete-account/confirm", %{"key" => "deadbeef"})

      assert redirected_to(conn) == "/dashboard/delete-account"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "rejects another user's key with the same generic error", c do
      attacker = insert(:user)
      attacker_request = request_deletion(attacker)

      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/delete-account/confirm", %{"key" => attacker_request.key})

      assert redirected_to(conn) == "/dashboard/delete-account"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
      assert Repo.get(User, c.user.id)
      assert Repo.get(User, attacker.id)
    end

    test "redirects when eligibility changed after the request", c do
      request = request_deletion(c.user)

      organization = insert(:organization)
      insert(:organization_user, user: c.user, organization: organization, role: "admin")

      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/dashboard/delete-account/confirm", %{"key" => request.key})

      assert redirected_to(conn) == "/dashboard/delete-account"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cannot be deleted right now"
    end
  end

  describe "POST /dashboard/delete-account/confirm" do
    test "deletes the account, logs out, redirects home", c do
      request = request_deletion(c.user)
      assert_email_sent(subject: "Hex.pm - Account deletion request")

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/delete-account/confirm", %{"key" => request.key})

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "permanently deleted"
      refute Repo.get(User, c.user.id)
      refute Plug.Conn.get_session(conn, "session_token")
      assert_email_sent(subject: "Hex.pm - Your account has been deleted")
    end

    test "a key cannot be reused", c do
      request = request_deletion(c.user)
      other = insert(:user)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/delete-account/confirm", %{"key" => request.key})

      assert redirected_to(conn) == "/"

      conn =
        build_conn()
        |> test_login(other)
        |> post("/dashboard/delete-account/confirm", %{"key" => request.key})

      assert redirected_to(conn) == "/dashboard/delete-account"
      assert Repo.get(User, other.id)
    end

    test "rejects with invalid key and deletes nothing", c do
      _request = request_deletion(c.user)

      conn =
        build_conn()
        |> test_login(c.user)
        |> post("/dashboard/delete-account/confirm", %{"key" => "deadbeef"})

      assert redirected_to(conn) == "/dashboard/delete-account"
      assert Repo.get(User, c.user.id)
    end
  end
end

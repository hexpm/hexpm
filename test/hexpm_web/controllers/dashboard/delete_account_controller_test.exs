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

  describe "full lifecycle" do
    test "maximal user deletes their account through the entire web flow" do
      # user_with_tfa: TFA-enabled factory user; extra unverified secondary email
      user =
        insert(:user_with_tfa,
          emails: [build(:email), build(:email, primary: false, public: false, verified: false)]
        )

      other_owner = insert(:user)
      org_admin = insert(:user)

      sole_package = insert(:package, package_owners: [build(:package_owner, user: user)])

      co_package =
        insert(:package,
          package_owners: [
            build(:package_owner, user: user),
            build(:package_owner, user: other_owner, level: "full")
          ]
        )

      release = insert(:release, package: sole_package, publisher: user)
      co_release = insert(:release, package: co_package, publisher: user)

      key = insert(:key, user: user)

      organization = insert(:organization)
      insert(:organization_user, user: org_admin, organization: organization, role: "admin")

      org_membership =
        insert(:organization_user, user: user, organization: organization, role: "write")

      old_log =
        insert(:audit_log,
          user: user,
          action: "user.update",
          user_data: %{"id" => user.id, "username" => user.username}
        )

      username = user.username
      email_ids = Enum.map(user.emails, & &1.id)

      # 1. the warnings page lists the sole-owned package
      conn = build_conn() |> test_login(user) |> get("/dashboard/delete-account")
      assert response(conn, 200) =~ sole_package.name
      refute response(conn, 200) =~ co_package.name

      # 2. request deletion
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/delete-account", %{"username" => username})

      assert redirected_to(conn) == "/dashboard/delete-account"
      request = Repo.get_by!(AccountDeletionRequest, user_id: user.id)
      assert_email_sent(subject: "Hex.pm - Account deletion request")

      # 3. follow the emailed link
      conn =
        build_conn()
        |> test_login(user)
        |> get("/dashboard/delete-account/confirm", %{"key" => request.key})

      assert response(conn, 200) =~ "Delete my account"

      # 4. final confirmation
      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/delete-account/confirm", %{"key" => request.key})

      assert redirected_to(conn) == "/"
      assert_email_sent(subject: "Hex.pm - Your account has been deleted")

      # user and credentials gone
      refute Repo.get(User, user.id)
      refute Repo.get(Hexpm.Accounts.Key, key.id)
      refute Repo.get(Hexpm.Accounts.OrganizationUser, org_membership.id)
      for email_id <- email_ids, do: refute(Repo.get(Hexpm.Accounts.Email, email_id))

      # packages and releases preserved with nulled publisher
      assert Repo.get(Hexpm.Repository.Package, sole_package.id)
      assert Repo.get(Hexpm.Repository.Package, co_package.id)
      assert Repo.get(Hexpm.Repository.Release, release.id).publisher_id == nil
      assert Repo.get(Hexpm.Repository.Release, co_release.id).publisher_id == nil

      # co-owned package keeps its other owner; sole-owned is orphaned
      sole_reloaded = Repo.get(Hexpm.Repository.Package, sole_package.id)
      co_reloaded = Repo.get(Hexpm.Repository.Package, co_package.id)
      assert [%{user_id: other_id}] = Repo.all(Ecto.assoc(co_reloaded, :package_owners))
      assert other_id == other_owner.id
      assert Repo.all(Ecto.assoc(sole_reloaded, :package_owners)) == []

      # organization survives with its admin
      assert Repo.get(Hexpm.Accounts.Organization, organization.id)

      # audit logs preserved; request + delete logs exist with snapshots
      assert Repo.get(Hexpm.Accounts.AuditLog, old_log.id).user_id == nil
      assert Repo.get(Hexpm.Accounts.AuditLog, old_log.id).user_data["username"] == username
      assert Repo.get_by(Hexpm.Accounts.AuditLog, action: "user.delete.request")
      assert Repo.get_by(Hexpm.Accounts.AuditLog, action: "user.delete")

      # username reserved against user signup and org creation
      params = %{"username" => username, "emails" => [%{"email" => Hexpm.Fake.sequence(:email)}]}
      audit = %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}
      assert {:error, _} = Users.add(params, audit: audit)

      assert {:error, _} =
               Hexpm.Accounts.Organizations.create(org_admin, %{"name" => username},
                 audit: audit_data(org_admin)
               )

      # public pages: profile 404s, package page renders with nil publisher
      assert build_conn() |> get("/users/#{username}") |> response(404)
      assert build_conn() |> get("/packages/#{sole_package.name}") |> response(200)
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

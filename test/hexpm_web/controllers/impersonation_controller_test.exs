defmodule HexpmWeb.ImpersonationControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.{AuditLog, User}
  alias Hexpm.AdminTasks.AuditLog, as: AdminAuditLog
  alias Hexpm.{UserSession, UserSessions}

  setup do
    %{moderator: insert(:user_with_tfa, role: "mod"), user: insert(:user)}
  end

  defp impersonate(c) do
    conn =
      build_conn()
      |> test_login(c.moderator)
      |> post("/dashboard/admin/users/#{c.user.username}/impersonate")

    assert redirected_to(conn) == "/dashboard"
    recycle(conn)
  end

  defp impersonation_session!(c) do
    Repo.get_by!(UserSession, user_id: c.user.id, impersonator_id: c.moderator.id)
  end

  describe "logging in as a user" do
    test "makes requests as the user and records the moderator", c do
      conn = c |> impersonate() |> get("/dashboard/profile")

      assert conn.assigns.current_user.id == c.user.id
      assert conn.assigns.impersonator.id == c.moderator.id
      assert conn.assigns.current_session.id == impersonation_session!(c).id

      assert html_response(conn, 200) =~ "id=\"impersonation-banner\""
      assert conn.resp_body =~ "#{c.moderator.username} is logged in as #{c.user.username}"

      assert [log] = Repo.all(AdminAuditLog)
      assert log.action == "impersonate_user"
      assert log.status == "ok"
      assert log.user_id == c.moderator.id
      assert log.params == %{"user" => c.user.username}
    end

    test "is hidden from the user", c do
      conn = c |> impersonate() |> get("/dashboard/sessions")

      assert html_response(conn, 200)
      assert UserSessions.all_for_user(c.user) == []
      refute Repo.exists?(from(l in AuditLog, where: l.user_id == ^c.user.id))
    end

    test "is not found for a user without the mod role", c do
      conn =
        build_conn()
        |> test_login(insert(:user))
        |> post("/dashboard/admin/users/#{c.user.username}/impersonate")

      assert response(conn, 404)
      refute Repo.exists?(from(s in UserSession, where: s.user_id == ^c.user.id))
    end

    test "asks the moderator to verify with sudo", c do
      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> post("/dashboard/admin/users/#{c.user.username}/impersonate")

      assert redirected_to(conn) == "/sudo"
      refute Repo.exists?(AdminAuditLog)
    end

    test "says why it was refused", c do
      conn =
        build_conn()
        |> test_login(c.moderator)
        |> post("/dashboard/admin/users/#{c.moderator.username}/impersonate")

      assert redirected_to(conn) == "/dashboard/admin/users/#{c.moderator.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ ":impersonator"
      refute get_session(conn, "impersonation_token")
    end

    test "is offered on the look up page of another user only", c do
      conn =
        build_conn()
        |> test_login(c.moderator)
        |> get("/dashboard/admin/users/#{c.user.username}")

      assert html_response(conn, 200) =~ "/dashboard/admin/users/#{c.user.username}/impersonate"

      path = "/dashboard/admin/users/#{c.moderator.username}"
      conn = build_conn() |> test_login(c.moderator) |> get(path)
      refute html_response(conn, 200) =~ "impersonate-form"
    end
  end

  describe "read-only" do
    test "refuses every write", c do
      conn = impersonate(c)
      refused = post(conn, "/dashboard/profile", %{"user" => %{"full_name" => "Changed"}})

      assert html_response(refused, 403) =~ "read-only admin session as #{c.user.username}"
      assert Repo.get!(User, c.user.id).full_name == c.user.full_name

      assert conn |> delete("/dashboard/keys", %{"key_name" => "any"}) |> response(403)
      assert conn |> post("/dashboard/billing-api/customer", %{}) |> response(403)
    end

    test "opens sudo-gated pages for GET without asking for sudo", c do
      conn = impersonate(c)

      assert conn |> get("/dashboard/keys") |> html_response(200)
      assert conn |> get("/dashboard/security") |> html_response(200)
    end

    test "doesn't send the moderator to sudo once their sudo window ends", c do
      {:ok, _session, token} = UserSessions.create_impersonation_session(c.user, c.moderator)

      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> init_test_session(%{"impersonation_token" => Base.encode64(token)})
        |> get("/dashboard/keys")

      assert html_response(conn, 200)
      assert conn.assigns.current_user.id == c.user.id
    end

    test "refuses the recovery codes and the login flows", c do
      conn = impersonate(c)

      for path <- [
            "/dashboard/security/recovery-codes",
            "/login",
            "/sudo",
            "/auth/github",
            "/auth/github/callback",
            "/email/verify?username=x&email=x&key=x",
            "/oauth/authorize",
            "/sso/org/acme",
            "/organizations/authorize",
            "/organizations/acme/authenticate",
            "/invites",
            "/%6Cogin"
          ] do
        assert conn |> get(path) |> response(403), path
      end
    end
  end

  describe "ending it" do
    test "stop revokes the session and returns to the moderator", c do
      conn = impersonate(c) |> post("/impersonation/stop")

      assert redirected_to(conn) == "/dashboard/admin/users/#{c.user.username}"
      assert impersonation_session!(c).revoked_at

      conn = conn |> recycle() |> get("/dashboard/profile")
      assert conn.assigns.current_user.id == c.moderator.id
      refute conn.assigns.impersonator
    end

    test "expiry returns to the moderator", c do
      conn = impersonate(c)

      c
      |> impersonation_session!()
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()

      conn = get(conn, "/dashboard/profile")
      assert conn.assigns.current_user.id == c.moderator.id
      refute get_session(conn, "impersonation_token")
    end

    test "losing the mod role returns to the moderator", c do
      conn = impersonate(c)
      c.moderator |> Ecto.Changeset.change(role: "basic") |> Repo.update!()

      conn = get(conn, "/dashboard/profile")
      assert conn.assigns.current_user.id == c.moderator.id
      refute conn.assigns.impersonator
    end

    test "logging out revokes both sessions and audits only the moderator's", c do
      conn = impersonate(c) |> post("/logout")

      assert redirected_to(conn) == "/"
      assert impersonation_session!(c).revoked_at

      assert Repo.one!(
               from(s in UserSession,
                 where: s.user_id == ^c.moderator.id and is_nil(s.impersonator_id),
                 select: s.revoked_at
               )
             )

      refute Repo.exists?(from(l in AuditLog, where: l.user_id == ^c.user.id))

      assert Repo.exists?(
               from(l in AuditLog,
                 where: l.user_id == ^c.moderator.id and l.action == "session.revoke"
               )
             )
    end
  end

  describe "the session token" do
    test "doesn't log in as the user on its own", c do
      {:ok, _session, token} = UserSessions.create_impersonation_session(c.user, c.moderator)

      conn =
        build_conn()
        |> init_test_session(%{"session_token" => Base.encode64(token)})
        |> get("/dashboard/profile")

      assert redirected_to(conn) =~ "/login"
    end

    test "doesn't log in as the user with another moderator's session", c do
      {:ok, _session, token} = UserSessions.create_impersonation_session(c.user, c.moderator)
      other = insert(:user, role: "mod")

      conn =
        build_conn()
        |> test_login(other)
        |> init_test_session(%{"impersonation_token" => Base.encode64(token)})
        |> get("/dashboard/profile")

      assert conn.assigns.current_user.id == other.id
      refute conn.assigns.impersonator
    end
  end
end

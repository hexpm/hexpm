defmodule HexpmWeb.Dashboard.AdminControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Oban.Testing, repo: Hexpm.RepoBase

  import ExUnit.CaptureLog

  alias Hexpm.AdminTasks
  alias Hexpm.AdminTasks.AuditLog, as: AdminAuditLog
  alias Hexpm.Accounts.{BlockedEmailDomain, Organization, OrganizationUser, PasswordReset, User}
  alias Hexpm.Repository.{Package, PackageOwner, Release}
  alias HexpmWeb.Dashboard.AdminView

  setup do
    stub(Hexpm.Billing.Mock, :get, fn _organization, _opts -> nil end)
    %{moderator: insert(:user_with_tfa, role: "mod")}
  end

  defp run_task(c, task, args, confirm \\ nil) do
    params = if confirm, do: %{"confirm" => confirm}, else: %{}

    build_conn()
    |> test_login(c.moderator)
    |> post("/dashboard/admin/tasks/#{task}", Map.put(params, "args", args))
  end

  defp get_page(c, path), do: build_conn() |> test_login(c.moderator) |> get(path)

  defp info(conn), do: Phoenix.Flash.get(conn.assigns.flash, :info)
  defp error(conn), do: Phoenix.Flash.get(conn.assigns.flash, :error)

  defp audit_log!(action), do: Repo.get_by!(AdminAuditLog, action: action)

  describe "access" do
    test "requires login" do
      conn = get(build_conn(), "/dashboard/admin")
      assert redirected_to(conn) == "/login?return=%2Fdashboard%2Fadmin"
    end

    test "is not found for a user without the mod role" do
      user = insert(:user)

      conn = build_conn() |> test_login(user) |> get("/dashboard/admin")
      assert response(conn, 404)

      conn = build_conn() |> test_login(user) |> get("/dashboard/admin/audit-log")
      assert response(conn, 404)

      conn = build_conn() |> test_login(user) |> get("/dashboard/admin/tasks/block_email_domain")
      assert response(conn, 404)

      for path <- [
            "/dashboard/admin/lookup?kind=user&name=#{user.username}",
            "/dashboard/admin/users/#{user.username}",
            "/dashboard/admin/packages/hexpm/decimal",
            "/dashboard/admin/organizations/acme"
          ] do
        conn = build_conn() |> test_login(user) |> get(path)
        assert response(conn, 404)
      end

      conn =
        build_conn()
        |> test_login(user)
        |> post("/dashboard/admin/tasks/block_email_domain", %{"args" => %{"domain" => "x.com"}})

      assert response(conn, 404)
      refute Repo.exists?(BlockedEmailDomain)
      refute Repo.exists?(AdminAuditLog)
    end

    test "asks a moderator to verify with sudo", c do
      conn = build_conn() |> test_login(c.moderator, sudo: false) |> get("/dashboard/admin")
      assert redirected_to(conn) == "/sudo"

      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> get("/dashboard/admin/tasks/block_email_domain")

      assert redirected_to(conn) == "/sudo"

      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> post("/dashboard/admin/tasks/block_email_domain", %{"args" => %{"domain" => "x.com"}})

      assert redirected_to(conn) == "/sudo"
      refute Repo.exists?(BlockedEmailDomain)
    end

    test "accepts the normal sudo window on every admin page", c do
      two_minutes_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -120)

      for path <- [
            "/dashboard/admin",
            "/dashboard/admin/audit-log",
            "/dashboard/admin/tasks/block_email_domain",
            "/dashboard/admin/users/#{c.moderator.username}"
          ] do
        conn = build_conn() |> test_login(c.moderator, sudo_at: two_minutes_ago) |> get(path)
        assert response(conn, 200)
      end

      conn =
        build_conn()
        |> test_login(c.moderator, sudo_at: two_minutes_ago)
        |> post("/dashboard/admin/tasks/block_email_domain", %{"args" => %{"domain" => "x.com"}})

      assert redirected_to(conn) == "/dashboard/admin"
      assert Repo.get_by(BlockedEmailDomain, domain: "x.com")
    end

    test "runs a task with the form's sudo token after sudo expired", c do
      token =
        HexpmWeb.Plugs.Sudo.generate_form_token(
          c.moderator.id,
          "POST",
          "/dashboard/admin/tasks/block_email_domain"
        )

      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> post("/dashboard/admin/tasks/block_email_domain", %{
          "args" => %{"domain" => "x.com"},
          "_sudo_token" => token
        })

      assert redirected_to(conn) == "/dashboard/admin"
      assert Repo.get_by(BlockedEmailDomain, domain: "x.com")
    end

    test "an unknown task is not found", c do
      conn = run_task(c, "eval", %{})
      assert response(conn, 404)

      conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/tasks/eval")
      assert response(conn, 404)

      for task <- ["send_email", "retry_oban_jobs", "backfill_doc_files"] do
        conn = run_task(c, task, %{})
        assert response(conn, 404)
      end
    end

    test "the sidebar links the admin pages for moderators only", c do
      conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/profile")
      assert response(conn, 200) =~ ~s(href="/dashboard/admin/audit-log")

      conn = build_conn() |> test_login(insert(:user)) |> get("/dashboard/profile")
      refute response(conn, 200) =~ ~s(href="/dashboard/admin)
    end
  end

  describe "GET /dashboard/admin" do
    test "lists only the tasks a look up page doesn't link", c do
      conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin")
      html = response(conn, 200)

      for section <- AdminView.sections(), task <- section.tasks do
        if section.lookup do
          refute html =~ ~s(href="/dashboard/admin/tasks/#{task.id}")
        else
          assert html =~ ~s(href="/dashboard/admin/tasks/#{task.id}")
        end

        refute html =~ ~s(action="/dashboard/admin/tasks/#{task.id}")
      end

      assert html =~ "block_email_domain"
    end

    test "lists the blocked domains with a link to unblock each", c do
      conn = get_page(c, "/dashboard/admin")
      assert response(conn, 200) =~ "No domains are blocked."

      :ok = AdminTasks.block_email_domain("farm.example", comment: "signup farm")

      html = response(get_page(c, "/dashboard/admin"), 200)
      assert html =~ "farm.example"
      assert html =~ "signup farm"

      assert html =~
               ~s(href="/dashboard/admin/tasks/unblock_email_domain?args[domain]=farm.example")
    end

    test "every task left off the list is linked from a look up page" do
      hexpm = %Hexpm.Repository.Repository{name: "hexpm"}

      linked =
        [
          AdminView.lookup_tasks(:user, %{user: %User{username: "bob"}}),
          AdminView.lookup_tasks(:package, %{package: %Package{name: "a", repository: hexpm}}),
          AdminView.lookup_tasks(:package, %{
            package: %Package{
              name: "a",
              repository: hexpm,
              search_disabled_at: DateTime.utc_now()
            }
          }),
          AdminView.lookup_tasks(:organization, %{organization: %Organization{name: "acme"}})
        ]
        |> Enum.concat()
        |> MapSet.new(fn {task, _prefill} -> task.id end)

      for section <- AdminView.sections(), section.lookup, task <- section.tasks do
        assert task.id in linked
      end
    end
  end

  describe "GET /dashboard/admin/tasks/:task" do
    test "renders only the task's own form", c do
      for section <- AdminView.sections(), task <- section.tasks do
        conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/tasks/#{task.id}")
        html = response(conn, 200)

        assert [_form] = Regex.scan(~r{action="/dashboard/admin/tasks/[a-z_]+"}, html)
        assert html =~ ~s(action="/dashboard/admin/tasks/#{task.id}")
        assert html =~ task.title
      end
    end

    test "renders the reasons and keeps browsers from filling the password", c do
      conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/tasks/remove_user")
      assert response(conn, 200) =~ "Seo spam"

      conn =
        build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/tasks/change_password")

      assert response(conn, 200) =~ ~s(autocomplete="new-password")
    end

    test "lists the blocked domains on the email domain tasks", c do
      :ok = AdminTasks.block_email_domain("farm.example", comment: "signup farm")

      for task <- ["block_email_domain", "unblock_email_domain"] do
        conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/tasks/#{task}")
        html = response(conn, 200)
        assert html =~ "farm.example"
        assert html =~ "signup farm"
      end

      conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/tasks/reset_tfa")
      refute response(conn, 200) =~ "farm.example"
    end

    test "fills in the text fields from the link", c do
      conn = get_page(c, "/dashboard/admin/tasks/reset_tfa?args[user]=bob")
      assert response(conn, 200) =~ ~s(value="bob")
    end

    test "lists the packages out of search on the search tasks", c do
      package = insert(:package, repository_id: 1)
      :ok = AdminTasks.disable_search(package.name)

      for task <- ["disable_search", "enable_search"] do
        conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/tasks/#{task}")
        assert response(conn, 200) =~ package.name
      end
    end
  end

  describe "POST /dashboard/admin/tasks/:task" do
    test "records the moderator in the audit log", c do
      conn =
        build_conn()
        |> put_req_header("user-agent", "Browser")
        |> test_login(c.moderator)
        |> post("/dashboard/admin/tasks/block_email_domain", %{
          "args" => %{"domain" => "farm.example", "comment" => "signup farm"}
        })

      assert redirected_to(conn) == "/dashboard/admin"
      assert info(conn) == "Block email domain: done."

      log = audit_log!("block_email_domain")
      assert log.user_id == c.moderator.id
      assert log.user_data["username"] == c.moderator.username
      assert log.user_agent == "Browser"
      assert log.remote_ip == "127.0.0.1"
      assert log.params == %{"domain" => "farm.example", "comment" => "signup farm"}
      assert log.status == "ok"
    end

    test "shows the error a task returned", c do
      conn = run_task(c, "reset_tfa", %{"user" => "nonexistent"})

      assert redirected_to(conn) == "/dashboard/admin"
      assert error(conn) == "Reset two-factor authentication: failed, :user_not_found."
      assert audit_log!("reset_tfa").status == "error"
    end

    test "shows a changeset error", c do
      :ok = AdminTasks.block_email_domain("farm.example")

      conn = run_task(c, "block_email_domain", %{"domain" => "farm.example"})
      assert error(conn) =~ "Block email domain: failed, domain "
    end

    test "shows an exception a task raised", c do
      organization = insert(:organization)
      expect(Hexpm.Billing.Mock, :get, 2, fn _name, _opts -> %{"subscription" => %{}} end)
      expect(Hexpm.Billing.Mock, :cancel, fn _name -> raise "billing service unavailable" end)

      log =
        capture_log(fn ->
          conn =
            run_task(
              c,
              "delete_organization",
              %{"organization" => organization.name},
              organization.name
            )

          assert error(conn) ==
                   "Delete organization: raised RuntimeError: billing service unavailable"
        end)

      assert log =~ "billing service unavailable"
      assert Repo.get(Organization, organization.id)
      assert audit_log!("delete_organization").status == "raised"
    end

    test "ignores arguments that are not a map of strings", c do
      conn =
        build_conn()
        |> test_login(c.moderator)
        |> post("/dashboard/admin/tasks/reset_tfa", %{"args" => %{"user" => %{"a" => "b"}}})

      assert error(conn) =~ ":user_not_found"
      assert audit_log!("reset_tfa").params == %{"user" => ""}
    end
  end

  describe "user tasks" do
    test "reset_tfa", c do
      user = insert(:user_with_tfa)

      conn = run_task(c, "reset_tfa", %{"user" => user.username})

      assert info(conn) =~ "done"
      refute User.tfa_enabled?(Repo.get!(User, user.id))
    end

    test "security_password_reset", c do
      user = insert(:user)

      conn =
        run_task(c, "security_password_reset", %{
          "user" => user.username,
          "disable_password" => "true"
        })

      assert info(conn) =~ "done"
      assert Repo.get!(User, user.id).password == nil
      assert Repo.get_by(PasswordReset, user_id: user.id)

      assert audit_log!("security_password_reset").params == %{
               "user" => user.username,
               "disable_password" => true,
               "revoke_all_access" => false
             }
    end

    test "change_password by email", c do
      email = Fake.sequence(:email)
      user = insert(:user, emails: [build(:email, email: email)])

      conn =
        run_task(c, "change_password", %{
          "user" => email,
          "password" => "new password"
        })

      assert info(conn) =~ "done"
      assert Bcrypt.verify_pass("new password", Repo.get!(User, user.id).password)
      assert audit_log!("change_password").params == %{"type" => "email", "user" => email}
    end

    test "change_password shows a too short password's error without the password", c do
      user = insert(:user)

      conn =
        run_task(c, "change_password", %{
          "user" => user.username,
          "password" => "short12"
        })

      assert error(conn) == "Change password: failed, password should be at least 8 character(s)."
      log = audit_log!("change_password")
      assert log.params == %{"type" => "username", "user" => user.username}
      refute log.result =~ "short12"
    end

    test "rename_user", c do
      user = insert(:user)

      run_task(c, "rename_user", %{"old_name" => user.username, "new_name" => "renamed"})

      assert Repo.get!(User, user.id).username == "renamed"
    end

    test "remove_user with a canned reason", c do
      user = insert(:user)

      conn =
        run_task(
          c,
          "remove_user",
          %{
            "user" => user.username,
            "delete_packages" => "true",
            "reason" => "spam_account"
          },
          user.username
        )

      assert info(conn) =~ "done"
      refute Repo.get(User, user.id)

      assert audit_log!("remove_user").params == %{
               "user" => user.username,
               "delete_packages" => true,
               "reason" => "spam_account"
             }
    end

    test "remove_user with a written reason", c do
      user = insert(:user)

      run_task(
        c,
        "remove_user",
        %{
          "user" => user.username,
          "reason" => "spam_account",
          "reason_text" => "You published spam."
        },
        user.username
      )

      refute Repo.get(User, user.id)
      assert audit_log!("remove_user").params["reason"] == "You published spam."
    end

    test "remove_user ignores a reason that is not a known id", c do
      user = insert(:user)

      run_task(c, "remove_user", %{"user" => user.username, "reason" => "made_up"}, user.username)

      refute Repo.get(User, user.id)
      assert audit_log!("remove_user").params["reason"] == nil
    end
  end

  describe "email domain tasks" do
    test "unblock_email_domain", c do
      :ok = AdminTasks.block_email_domain("farm.example")

      conn = run_task(c, "unblock_email_domain", %{"domain" => "farm.example"})

      assert info(conn) =~ "done"
      refute Repo.exists?(BlockedEmailDomain)
    end
  end

  describe "package tasks" do
    test "add_owner", c do
      package = insert(:package)
      insert(:package_owner, package: package, user: insert(:user))
      user = insert(:user)

      conn =
        run_task(c, "add_owner", %{
          "package" => package.name,
          "user" => user.username,
          "level" => "full"
        })

      assert info(conn) =~ "done"

      assert %{level: "full"} =
               Repo.get_by!(PackageOwner, package_id: package.id, user_id: user.id)

      assert audit_log!("add_owner").params == %{
               "package" => package.name,
               "user" => user.username,
               "level" => "full"
             }
    end

    test "remove_owner", c do
      package = insert(:package)
      insert(:package_owner, package: package, user: insert(:user))
      user = insert(:user)
      insert(:package_owner, package: package, user: user)

      conn = run_task(c, "remove_owner", %{"package" => package.name, "user" => user.username})

      assert info(conn) =~ "done"
      refute Repo.get_by(PackageOwner, package_id: package.id, user_id: user.id)
    end

    test "allow_republish", c do
      package = insert(:package)
      old_time = ~U[2020-01-01 00:00:00Z]
      release = insert(:release, package: package, version: "1.0.0", inserted_at: old_time)

      run_task(c, "allow_republish", %{
        "package" => package.name,
        "version" => "1.0.0",
        "organization" => ""
      })

      assert DateTime.after?(Repo.get!(Release, release.id).inserted_at, old_time)
    end

    test "remove_release", c do
      package = insert(:package)
      release = insert(:release, package: package, version: "1.0.0")
      insert(:release, package: package, version: "2.0.0")

      conn =
        run_task(
          c,
          "remove_release",
          %{
            "repository" => "hexpm",
            "package" => package.name,
            "version" => "1.0.0",
            "reason" => ""
          },
          package.name
        )

      assert info(conn) =~ "done"
      refute Repo.get(Release, release.id)
    end

    test "remove_package", c do
      package = insert(:package)
      insert(:release, package: package)

      conn =
        run_task(
          c,
          "remove_package",
          %{"repository" => "hexpm", "package" => package.name},
          package.name
        )

      assert info(conn) =~ "done"
      refute Repo.get(Package, package.id)
    end
  end

  describe "search tasks" do
    test "disable_search and enable_search", c do
      package = insert(:package, repository_id: 1)

      run_task(c, "disable_search", %{"package" => package.name, "delete_index" => "true"})
      assert Repo.get!(Package, package.id).search_disabled_at

      assert audit_log!("disable_search").params == %{
               "package" => package.name,
               "delete_index" => true,
               "notify" => false
             }

      run_task(c, "enable_search", %{"package" => package.name})
      refute Repo.get!(Package, package.id).search_disabled_at
    end
  end

  describe "organization tasks" do
    test "remove_organization_member", c do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: insert(:user))
      user = insert(:user)
      member = insert(:organization_user, organization: organization, user: user)

      conn =
        run_task(c, "remove_organization_member", %{
          "organization" => organization.name,
          "user" => user.username
        })

      assert info(conn) =~ "done"
      refute Repo.get(OrganizationUser, member.id)
    end

    test "rename_organization", c do
      organization = insert(:organization)

      run_task(c, "rename_organization", %{
        "old_name" => organization.name,
        "new_name" => "renamed"
      })

      assert Repo.get!(Organization, organization.id).name == "renamed"
    end

    test "delete_organization_data", c do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id)

      name = repository.organization.name
      conn = run_task(c, "delete_organization_data", %{"organization" => name}, name)

      assert info(conn) =~ "done"
      refute Repo.get(Package, package.id)
      assert Repo.get(Organization, repository.organization.id)
    end

    test "delete_organization", c do
      organization = insert(:organization)

      conn =
        run_task(
          c,
          "delete_organization",
          %{"organization" => organization.name, "unless_billing_live" => "true"},
          organization.name
        )

      assert info(conn) =~ "done"
      refute Repo.get(Organization, organization.id)

      assert audit_log!("delete_organization").params == %{
               "organization" => organization.name,
               "delete_data" => false,
               "unless_billing_live" => true
             }
    end
  end

  describe "confirming a danger task" do
    test "renders what it acts on and runs nothing until the name is typed", c do
      user = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: user)
      args = %{"user" => user.username, "delete_packages" => "true", "reason" => "spam_account"}

      token =
        HexpmWeb.Plugs.Sudo.generate_form_token(
          c.moderator.id,
          "POST",
          "/dashboard/admin/tasks/remove_user"
        )

      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> post("/dashboard/admin/tasks/remove_user", %{"args" => args, "_sudo_token" => token})

      html = response(conn, 200)
      assert html =~ "Review Remove user"
      assert html =~ hd(user.emails).email
      assert html =~ "Deletes the packages only #{user.username} owns: #{package.name}."
      assert html =~ "Emails the reason to #{hd(user.emails).email}."
      assert html =~ "Type #{user.username} to confirm"
      assert html =~ ~s(action="/dashboard/admin/tasks/remove_user")

      assert [_, ^token] =
               Regex.run(~r/id="confirm-form".*?name="_sudo_token" value="([^"]+)"/s, html)

      assert html =~ ~s(name="args[delete_packages]" value="true")
      assert Repo.get(User, user.id)
      refute Repo.exists?(AdminAuditLog)

      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> post("/dashboard/admin/tasks/remove_user", %{
          "args" => args,
          "_sudo_token" => token,
          "confirm" => "someone_else"
        })

      assert response(conn, 200) =~ "That isn't #{user.username}."
      assert Repo.get(User, user.id)
      refute Repo.exists?(AdminAuditLog)

      conn =
        build_conn()
        |> test_login(c.moderator, sudo: false)
        |> post("/dashboard/admin/tasks/remove_user", %{
          "args" => args,
          "_sudo_token" => token,
          "confirm" => user.username
        })

      assert redirected_to(conn) == "/dashboard/admin"
      refute Repo.get(User, user.id)
      refute Repo.get(Package, package.id)
    end

    test "takes the username when the task was given an email", c do
      user = insert(:user)
      email = hd(user.emails).email

      conn = run_task(c, "remove_user", %{"user" => email}, email)
      assert response(conn, 200) =~ "That isn't #{user.username}."
      assert Repo.get(User, user.id)

      run_task(c, "remove_user", %{"user" => email}, user.username)
      refute Repo.get(User, user.id)
    end

    test "says what is missing instead of offering to run", c do
      conn = run_task(c, "remove_user", %{"user" => "nonexistent"})
      html = response(conn, 200)

      assert html =~ "Nothing to run, :user_not_found."
      refute html =~ ~s(id="confirm-form")

      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")

      conn =
        run_task(c, "remove_release", %{
          "repository" => "hexpm",
          "package" => package.name,
          "version" => "2.0.0"
        })

      assert response(conn, 200) =~ "Nothing to run, :release_not_found."
      refute Repo.exists?(AdminAuditLog)
    end

    test "renders for every danger task", c do
      for section <- AdminView.sections(), task <- section.tasks, task.danger do
        conn = run_task(c, task.id, %{})
        assert response(conn, 200) =~ "Review #{task.title}"
      end

      refute Repo.exists?(AdminAuditLog)
    end

    test "lists the releases and owners a removal affects", c do
      owner = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: owner)
      insert(:release, package: package, version: "1.0.0")
      insert(:release, package: package, version: "1.1.0")
      args = %{"repository" => "hexpm", "package" => package.name, "reason" => "malware"}

      html = response(run_task(c, "remove_package", args), 200)
      assert html =~ "Deletes #{package.name} and its 2 releases."
      assert html =~ "Emails the reason to the owners: #{owner.username}."

      html = response(run_task(c, "remove_release", Map.put(args, "version", "1.0.0")), 200)
      assert html =~ "Deletes #{package.name} 1.0.0, published"
      assert html =~ "1 release remain"
    end

    test "names only the verified primary address a user removal emails", c do
      user =
        insert(:user,
          emails: [
            build(:email, email: "primary@example.com"),
            build(:email,
              email: "secondary@example.com",
              primary: false,
              public: false,
              gravatar: false
            )
          ]
        )

      html =
        response(
          run_task(c, "remove_user", %{"user" => user.username, "reason" => "spam_account"}),
          200
        )

      assert html =~ "Emails the reason to primary@example.com."
      refute html =~ "secondary@example.com."

      user =
        insert(:user,
          emails: [
            build(:email, email: "unverified@example.com", verified: false),
            build(:email,
              email: "verified@example.com",
              primary: false,
              public: false,
              gravatar: false
            )
          ]
        )

      html =
        response(
          run_task(c, "remove_user", %{"user" => user.username, "reason" => "spam_account"}),
          200
        )

      assert html =~ "Sends no email, #{user.username} has no verified primary address."
    end

    test "says a package without owners gets no removal email", c do
      package = insert(:package)
      args = %{"repository" => "hexpm", "package" => package.name, "reason" => "malware"}

      html = response(run_task(c, "remove_package", args), 200)
      assert html =~ "Sends no email, the package has no owners."

      repository = insert(:repository)
      private = insert(:package, repository_id: repository.id)
      args = %{"repository" => repository.name, "package" => private.name, "reason" => "malware"}

      html = response(run_task(c, "remove_package", args), 200)
      assert html =~ "Emails the reason to the organization&#39;s admins."
    end

    test "shows the billing an organization deletion meets", c do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: insert(:user))

      expect(Hexpm.Billing.Mock, :get, 2, fn _name, _opts ->
        %{"subscription" => %{"status" => "trialing"}}
      end)

      args = %{"organization" => organization.name}

      html = response(run_task(c, "delete_organization", args), 200)
      assert html =~ "Billing is trialing, and the subscription is cancelled first."
      assert html =~ "1 membership"

      html = response(run_task(c, "delete_organization_data", args), 200)
      assert html =~ "Refused, billing is trialing."
    end
  end

  describe "looking up" do
    test "sends each kind to its page", c do
      for {kind, name, path} <- [
            {"user", " bob ", "/dashboard/admin/users/bob"},
            {"package", "decimal", "/dashboard/admin/packages/hexpm/decimal"},
            {"package", "acme/api", "/dashboard/admin/packages/acme/api"},
            {"organization", "acme", "/dashboard/admin/organizations/acme"}
          ] do
        conn = get_page(c, "/dashboard/admin/lookup?" <> URI.encode_query(kind: kind, name: name))
        assert redirected_to(conn) == path
      end

      conn = get_page(c, "/dashboard/admin/lookup?kind=user&name=")
      assert redirected_to(conn) == "/dashboard/admin"
      assert error(conn) == "Enter a name to look up."
    end

    test "a user page shows the account and links its tasks", c do
      user = insert(:user)
      email = hd(user.emails).email
      package = insert(:package)
      insert(:package_owner, package: package, user: user)
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: user, role: "admin")
      AdminTasks.reset_tfa(email)
      AdminTasks.reset_tfa("someone_else")

      html = response(get_page(c, "/dashboard/admin/users/#{email}"), 200)

      assert html =~ "User #{user.username}"
      assert html =~ ~s(href="/users/#{user.username}")
      assert html =~ email
      assert html =~ ~s(href="/dashboard/admin/packages/hexpm/#{package.name}")
      assert html =~ "only this user"
      assert html =~ ~s(href="/dashboard/admin/organizations/#{organization.name}")
      assert html =~ ~s(href="/dashboard/admin/tasks/reset_tfa?args[user]=#{user.username}")
      assert html =~ "reset_tfa"
      refute html =~ "someone_else"
    end

    test "a user without a verified primary address has no public page", c do
      user = insert(:user, emails: [build(:email, verified: false)])

      html = response(get_page(c, "/dashboard/admin/users/#{user.username}"), 200)

      assert html =~ "none, no verified primary address"
      refute html =~ ~s(href="/users/#{user.username}")
    end

    test "a package page shows its owners and releases", c do
      owner = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: owner, level: "maintainer")
      insert(:release, package: package, version: "1.0.0")
      AdminTasks.disable_search(package.name)

      html = response(get_page(c, "/dashboard/admin/packages/hexpm/#{package.name}"), 200)

      assert html =~ "Package #{package.name}"
      assert html =~ ~s(href="/packages/#{package.name}")
      assert html =~ ~s(href="/dashboard/admin/users/#{owner.username}")
      assert html =~ "maintainer"
      assert html =~ "1.0.0"
      assert html =~ "disable_search"
      assert html =~ "/dashboard/admin/tasks/enable_search?"
      refute html =~ "/dashboard/admin/tasks/disable_search?"
    end

    test "a private package page points at its organization", c do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id)

      html =
        response(get_page(c, "/dashboard/admin/packages/#{repository.name}/#{package.name}"), 200)

      assert html =~ "Package #{repository.name}/#{package.name}"
      assert html =~ "none, only members of the organization can open it"
      refute html =~ ~s(href="/packages/#{repository.name}/#{package.name}")
      assert html =~ ~s(href="/dashboard/admin/organizations/#{repository.organization.name}")
      refute html =~ "/dashboard/admin/tasks/add_owner?"
    end

    test "an organization page shows members, packages and billing", c do
      repository = insert(:repository)
      organization = repository.organization
      package = insert(:package, repository_id: repository.id)
      member = insert(:user)
      insert(:organization_user, organization: organization, user: member, role: "admin")

      expect(Hexpm.Billing.Mock, :get, fn _name, _opts ->
        %{"subscription" => %{"status" => "active"}}
      end)

      html = response(get_page(c, "/dashboard/admin/organizations/#{organization.name}"), 200)

      assert html =~ "Organization #{organization.name}"
      assert html =~ ~s(href="/orgs/#{organization.name}")
      assert html =~ ~s(href="/dashboard/admin/users/#{member.username}")
      assert html =~ ~s(href="/dashboard/admin/packages/#{repository.name}/#{package.name}")
      assert html =~ "active"
      assert html =~ "/dashboard/admin/tasks/delete_organization?"
    end

    test "something that does not exist goes back to the tasks", c do
      for path <- [
            "/dashboard/admin/users/nonexistent",
            "/dashboard/admin/packages/hexpm/nonexistent",
            "/dashboard/admin/packages/nonexistent/decimal",
            "/dashboard/admin/organizations/nonexistent"
          ] do
        conn = get_page(c, path)
        assert redirected_to(conn) == "/dashboard/admin"
        assert error(conn) =~ "Look up failed"
      end
    end
  end

  describe "GET /dashboard/admin/audit-log" do
    test "lists the runs with who ran them", c do
      user = insert(:user)

      AdminTasks.rename_user(user.username, "renamed",
        audit: audit_data(c.moderator, remote_ip: "10.0.0.1")
      )

      AdminTasks.reset_tfa("nonexistent")

      conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/audit-log")
      html = response(conn, 200)

      assert html =~ "rename_user"
      assert html =~ c.moderator.username
      assert html =~ "10.0.0.1"
      assert html =~ "renamed"
      assert html =~ "CONSOLE"
      assert html =~ ":user_not_found"
    end

    test "says when nothing has been run", c do
      conn = build_conn() |> test_login(c.moderator) |> get("/dashboard/admin/audit-log")
      assert response(conn, 200) =~ "No admin tasks have been run."
    end
  end
end

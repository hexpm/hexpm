defmodule HexpmWeb.Dashboard.OrganizationWorkloadIdentitiesTest do
  use HexpmWeb.ConnCase, async: false

  import Mox

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.WorkloadIdentities
  alias Hexpm.WorkloadIdentities.WorkloadIdentity

  setup :verify_on_exit!

  setup do
    admin = insert(:user_with_tfa)
    writer = insert(:user)
    reader = insert(:user)

    repository =
      insert(:repository,
        organization:
          build(:organization,
            organization_users: [
              build(:organization_user, user: admin, role: "admin"),
              build(:organization_user, user: writer, role: "write"),
              build(:organization_user, user: reader, role: "read")
            ]
          )
      )

    %{admin: admin, writer: writer, reader: reader, organization: repository.organization}
  end

  defp path(organization), do: "/dashboard/orgs/#{organization.name}/workload-identities"

  defp identity_params(params) do
    %{
      "workload_identity" =>
        Map.merge(
          %{"provider" => "github", "repository_owner" => "acme", "repository" => "widget"},
          params
        )
    }
  end

  describe "GET /dashboard/orgs/:dashboard_org/workload-identities" do
    test "shows the workload identities and the form to an admin", %{
      admin: admin,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml",
        packages: ["widget", "gadget"]
      )

      body =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"
      assert body =~ "release.yml"
      assert body =~ "widget, gadget"
      assert body =~ "add-workload-identity-form"
      refute body =~ "Two-factor authentication on your account is required"
      refute body =~ ~r/<fieldset[^>]*\sdisabled[\s>]/
    end

    test "shows each workload identity's coverage", %{admin: admin, organization: organization} do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/all",
        workflow: "release.yml"
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/both",
        workflow: "release.yml",
        packages: ["private_one"],
        covers_public: true,
        public_packages: ["public_one", "public_two"]
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/public",
        workflow: "release.yml",
        covers_private: false,
        packages: [],
        covers_public: true
      )

      document =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()

      coverage = fn repository ->
        document
        |> LazyHTML.query("li[id^=workload-identity-]")
        |> Enum.find(&(LazyHTML.text(&1) =~ repository))
        |> LazyHTML.query("p")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()))
        |> Enum.filter(&String.match?(&1, ~r/^(Private|Public):/))
      end

      assert coverage.("acme/all") == ["Private: all packages"]
      assert coverage.("acme/both") == ["Private: private_one", "Public: public_one, public_two"]
      assert coverage.("acme/public") == ["Public: all owned packages"]
    end

    test "offers only public packages without active billing", %{
      admin: admin,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(billing_active: false, trial_end: nil)
      |> Repo.update!()

      document =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()

      assert LazyHTML.text(document) =~
               "Private packages and the read role need an active billing subscription."

      assert document
             |> LazyHTML.query("#workload_identity_role option[value=read][disabled]")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#workload_identity_role option[value=write][selected]")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#workload_identity_covers_private[disabled]")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#workload_identity_covers_private[checked]")
             |> Enum.count() == 0

      assert document
             |> LazyHTML.query("#workload_identity_covers_public[checked]")
             |> Enum.count() == 1
    end

    test "checks private packages and leaves public packages unchecked in a new form", %{
      admin: admin,
      organization: organization
    } do
      document =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()

      assert document
             |> LazyHTML.query("#workload_identity_covers_private[checked]")
             |> Enum.count() == 1

      assert document |> LazyHTML.query("#workload_identity_covers_public") |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#workload_identity_covers_public[checked]")
             |> Enum.count() == 0

      assert document |> LazyHTML.query("#workload_identity_public_packages") |> Enum.count() == 1
    end

    test "disables the form for an admin without 2FA and links to enabling it", %{
      organization: organization
    } do
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          repository: "acme/widget"
        )

      body =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"

      assert body =~
               "Two-factor authentication on your account is required to add or remove workload identities."

      assert body =~
               ~s(href="/dashboard/security?return=#{URI.encode_www_form(path(organization))}")

      assert body =~ "add-workload-identity-form"
      assert body =~ ~r/<fieldset[^>]*\sdisabled[\s>]/
      refute body =~ "remove-workload-identity-#{identity.id}"
    end

    test "shows the workload identities without the form to a write member", %{
      writer: writer,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        repository: "acme/widget"
      )

      body =
        build_conn()
        |> test_login(writer)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"
      assert body =~ "Only organization admins can add and remove workload identities."
      refute body =~ "add-workload-identity-form"
    end

    test "shows the workload identities without the form to a read member", %{
      reader: reader,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        repository: "acme/widget"
      )

      body =
        build_conn()
        |> test_login(reader)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"
      refute body =~ "add-workload-identity-form"
    end

    test "requires sudo", %{admin: admin, organization: organization} do
      conn =
        build_conn()
        |> test_login(admin, sudo: false)
        |> get(path(organization))

      assert redirected_to(conn) =~ "/sudo"
    end

    test "returns 404 and hides the tab when the feature is disabled", %{
      admin: admin,
      organization: organization
    } do
      put_feature_flag(:workload_identity, mode: :off)

      conn = build_conn() |> test_login(admin) |> get(path(organization))
      assert conn.status == 404

      body =
        build_conn()
        |> test_login(admin)
        |> get("/dashboard/orgs/#{organization.name}")
        |> html_response(200)

      refute body =~ path(organization)
    end

    test "shows the page and the tab in beta for an organization on the list", %{
      admin: admin,
      organization: organization
    } do
      put_feature_flag(:workload_identity,
        mode: :beta,
        beta_users: [],
        beta_organizations: [organization.name]
      )

      body = build_conn() |> test_login(admin) |> get(path(organization)) |> html_response(200)
      assert body =~ ~s(href="#{path(organization)}")
    end

    test "returns 404 and hides the tab in beta for an organization not on the list", %{
      admin: admin,
      organization: organization
    } do
      put_feature_flag(:workload_identity,
        mode: :beta,
        beta_users: [admin.username],
        beta_organizations: ["someone-else"]
      )

      conn = build_conn() |> test_login(admin) |> get(path(organization))
      assert conn.status == 404

      body =
        build_conn()
        |> test_login(admin)
        |> get("/dashboard/orgs/#{organization.name}")
        |> html_response(200)

      refute body =~ path(organization)
    end
  end

  describe "POST /dashboard/orgs/:dashboard_org/workload-identities" do
    test "adds a workload identity", %{admin: admin, organization: organization} do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read", "workflow" => ""}))

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "added"

      assert [identity] = WorkloadIdentities.list(organization)
      assert identity.role == "read"
      assert identity.workflow == ""
      assert Repo.get_by(AuditLog, action: "organization.workload_identity.add")
    end

    test "adds a workload identity for every repository of the owner", %{
      admin: admin,
      organization: organization
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 11}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read", "repository" => ""}))

      assert redirected_to(conn) == path(organization)

      body =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "Any repository owned by acme"
    end

    test "renders errors for an invalid workload identity", %{
      admin: admin,
      organization: organization
    } do
      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{"role" => "write", "packages" => "widget"})
        )

      body = html_response(conn, 400)
      assert body =~ "is required for the write role"
      assert body =~ ~s(value="widget")
      assert WorkloadIdentities.list(organization) == []
    end

    test "adds a workload identity for public packages only", %{
      admin: admin,
      organization: organization
    } do
      insert(:package,
        name: "public_one",
        package_owners: [build(:package_owner, user: organization.user, level: "full")]
      )

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "false",
            "packages" => "ignored",
            "covers_public" => "true",
            "public_packages" => "public_one"
          })
        )

      assert redirected_to(conn) == path(organization)

      assert [identity] = WorkloadIdentities.list(organization)
      assert identity.covers_private == false
      assert identity.packages == []
      assert identity.covers_public == true
      assert identity.public_packages == ["public_one"]
    end

    test "refuses a public package the organization doesn't own and keeps the form", %{
      admin: admin,
      organization: organization
    } do
      package = insert(:package, package_owners: [build(:package_owner, user: admin)])

      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "false",
            "packages" => "private_one",
            "covers_public" => "true",
            "public_packages" => package.name
          })
        )

      body = html_response(conn, 400)

      assert body =~
               "must be public packages the organization owns, not #{package.name}"

      document = LazyHTML.from_document(body)

      assert document
             |> LazyHTML.query("#workload_identity_covers_public[checked]")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#workload_identity_covers_private[checked]")
             |> Enum.count() == 0

      assert document
             |> LazyHTML.query("#workload_identity_public_packages")
             |> LazyHTML.attribute("value") == [package.name]

      assert document
             |> LazyHTML.query("#workload_identity_packages")
             |> LazyHTML.attribute("value") == ["private_one"]

      assert WorkloadIdentities.list(organization) == []
    end

    test "requires private packages, public packages or both for the write role", %{
      admin: admin,
      organization: organization
    } do
      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "false",
            "covers_public" => "false"
          })
        )

      assert html_response(conn, 400) =~ "select private packages, public packages or both"
      assert WorkloadIdentities.list(organization) == []
    end

    test "keeps the typed workflow when the repository name is missing", %{
      admin: admin,
      organization: organization
    } do
      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{"role" => "read", "repository" => "", "workflow" => "ci.yml"})
        )

      body = html_response(conn, 400)
      assert body =~ "must be empty when every repository matches"
      assert body =~ ~s(value="ci.yml")
      assert WorkloadIdentities.list(organization) == []
    end

    test "requires an environment for a write workload identity from a public repository", %{
      admin: admin,
      organization: organization
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}, "visibility" => "public"}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{"role" => "write", "workflow" => "publish.yml"})
        )

      body = html_response(conn, 400)
      assert body =~ "is required for a public repository"
      assert body =~ ~s(value="publish.yml")
      refute body =~ ~s(value="22")
      assert WorkloadIdentities.list(organization) == []
    end

    test "refuses a write member", %{writer: writer, organization: organization} do
      conn =
        build_conn()
        |> test_login(writer)
        |> post(path(organization), identity_params(%{"role" => "read"}))

      assert conn.status == 400
      assert WorkloadIdentities.list(organization) == []
    end

    test "requires 2FA on the admin's account", %{organization: organization} do
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read"}))

      assert redirected_to(conn) == "/dashboard/security"
      assert get_session(conn, :tfa_return_to) == path(organization)
      assert WorkloadIdentities.list(organization) == []
    end

    test "refuses private packages and the read role without active billing", %{
      admin: admin,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(billing_active: false, trial_end: nil)
      |> Repo.update!()

      body =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read"}))
        |> html_response(400)

      assert body =~ "needs an active billing subscription"

      body =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "true",
            "covers_public" => "false"
          })
        )
        |> html_response(400)

      assert body =~ "private packages need an active billing subscription"
      assert WorkloadIdentities.list(organization) == []
    end

    test "adds a workload identity for public packages without active billing", %{
      admin: admin,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(billing_active: false, trial_end: nil)
      |> Repo.update!()

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "false",
            "covers_public" => "true"
          })
        )

      assert redirected_to(conn) == path(organization)
      assert [identity] = WorkloadIdentities.list(organization)
      assert identity.covers_public == true
    end
  end

  describe "DELETE /dashboard/orgs/:dashboard_org/workload-identities/:id" do
    test "removes a workload identity", %{admin: admin, organization: organization} do
      identity = insert(:organization_workload_identity, organization: organization)

      conn =
        build_conn()
        |> test_login(admin)
        |> delete("#{path(organization)}/#{identity.id}")

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "removed"
      refute Repo.get(WorkloadIdentity, identity.id)
    end

    test "refuses another organization's workload identity", %{
      admin: admin,
      organization: organization
    } do
      identity = insert(:organization_workload_identity)

      conn =
        build_conn()
        |> test_login(admin)
        |> delete("#{path(organization)}/#{identity.id}")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
      assert Repo.get(WorkloadIdentity, identity.id)
    end

    test "refuses a write member", %{writer: writer, organization: organization} do
      identity = insert(:organization_workload_identity, organization: organization)

      conn =
        build_conn()
        |> test_login(writer)
        |> delete("#{path(organization)}/#{identity.id}")

      assert conn.status == 400
      assert Repo.get(WorkloadIdentity, identity.id)
    end
  end

  describe "adding rate limit" do
    setup do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
      on_exit(fn -> PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage) end)
      align_to_throttle_bucket(60 * 60_000)
      :ok
    end

    test "refuses before asking GitHub once the limit is reached", %{
      admin: admin,
      organization: organization
    } do
      for _ <- 1..20, do: HexpmWeb.Plugs.Attack.workload_identity_lookup_throttle(admin.id)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read"}))

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      assert WorkloadIdentities.list(organization) == []
    end

    test "doesn't count invalid submissions", %{admin: admin, organization: organization} do
      for _ <- 1..25 do
        conn =
          build_conn()
          |> test_login(admin)
          |> post(path(organization), identity_params(%{"role" => "write"}))

        assert conn.status == 400
      end

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read"}))

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "added"
    end
  end

  describe "removing a member" do
    test "the dialog says the organization's workload identities stay", %{
      admin: admin,
      organization: organization
    } do
      stub(Hexpm.Billing.Mock, :get, fn _name, _opts -> nil end)

      body =
        build_conn()
        |> test_login(admin)
        |> get("/dashboard/orgs/#{organization.name}/members")
        |> html_response(200)

      refute body =~ "Removing a member doesn't change"

      insert(:organization_workload_identity, organization: organization)
      insert(:organization_workload_identity, organization: organization)

      body =
        build_conn()
        |> test_login(admin)
        |> get("/dashboard/orgs/#{organization.name}/members")
        |> html_response(200)

      assert body =~
               "Removing a member doesn't change the organization's 2 workload identities"

      assert body =~ ~s(href="#{path(organization)}")
    end
  end
end

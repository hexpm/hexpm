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
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, workload_identity: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

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

    test "refuses an organization without active billing", %{
      admin: admin,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Repo.update!()

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read"}))

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no active billing subscription"
      assert WorkloadIdentities.list(organization) == []
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

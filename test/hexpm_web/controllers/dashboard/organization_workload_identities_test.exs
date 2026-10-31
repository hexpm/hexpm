defmodule HexpmWeb.Dashboard.OrganizationWorkloadIdentitiesTest do
  use HexpmWeb.ConnCase, async: false

  import Mox

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.WorkloadIdentities
  alias Hexpm.WorkloadIdentities.{TrustedRepository, WorkloadIdentity}

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

  defp repositories(names) do
    names
    |> Enum.with_index(1)
    |> Enum.map(fn {name, index} -> %TrustedRepository{name: name, id: "#{index}#{index}"} end)
  end

  defp normalized_text(node),
    do: node |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  defp identity_params(params) do
    %{
      "workload_identity" =>
        Map.merge(
          %{"provider" => "github", "repository_owner" => "acme", "repositories" => "widget"},
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
        repositories: repositories(["acme/widget"]),
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
        repositories: repositories(["acme/all"]),
        workflow: "release.yml"
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/both"]),
        workflow: "release.yml",
        packages: ["private_one"],
        covers_public: true,
        public_packages: ["public_one", "public_two"]
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/public"]),
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

      can = fn repository ->
        document
        |> LazyHTML.query("li[id^=workload-identity-]")
        |> Enum.find(&(LazyHTML.text(&1) =~ repository))
        |> LazyHTML.query("dd ul li")
        |> Enum.map(&normalized_text/1)
      end

      assert can.("acme/all") == [
               "Publish and create every package in #{organization.name}, and fetch them"
             ]

      assert can.("acme/both") == [
               "Publish and create these packages in #{organization.name}: private_one",
               "Fetch every package in #{organization.name}",
               "Publish public packages: public_one, public_two"
             ]

      assert can.("acme/public") == [
               "Publish public packages: every public package #{organization.name} owns"
             ]
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
             |> LazyHTML.query("#workload-identity-role-read[disabled]")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#workload-identity-role-write[checked]")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#workload-identity-role-write[disabled]")
             |> Enum.count() == 0

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
          repositories: repositories(["acme/widget"])
        )

      body =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"

      assert body =~
               "Two-factor authentication on your account is required to add, change or remove workload identities."

      assert body =~
               ~s(href="/dashboard/security?return=#{URI.encode_www_form(path(organization))}")

      assert body =~ "add-workload-identity-form"
      assert body =~ ~r/<fieldset[^>]*\sdisabled[\s>]/
      refute body =~ "remove-workload-identity-#{identity.id}"
      refute body =~ "#{path(organization)}/#{identity.id}/edit"
    end

    test "shows the workload identities without the form to a write member", %{
      writer: writer,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        repositories: repositories(["acme/widget"])
      )

      body =
        build_conn()
        |> test_login(writer)
        |> get(path(organization))
        |> html_response(200)

      assert body =~ "acme/widget"
      assert body =~ "Only organization admins can add, change and remove workload identities."
      refute body =~ "add-workload-identity-form"
    end

    test "shows the workload identities without the form to a read member", %{
      reader: reader,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        repositories: repositories(["acme/widget"])
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
        |> post(path(organization), identity_params(%{"role" => "read", "repositories" => ""}))

      assert redirected_to(conn) == path(organization)

      assert [%{repositories: [], repository_owner_id: "11"}] =
               WorkloadIdentities.list(organization)

      text =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()
        |> normalized_text()

      assert text =~ "Every repository acme has on GitHub Workflow any · Environment any"
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
          identity_params(%{"role" => "read", "repositories" => "", "workflow" => "ci.yml"})
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
      assert body =~ "is required because acme/widget is public"
      assert body =~ ~s(value="publish.yml")
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

    test "re-renders an add refused without billing with private packages off", %{
      admin: admin,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(billing_active: false, trial_end: nil)
      |> Repo.update!()

      document =
        build_conn()
        |> test_login(admin)
        |> post(
          path(organization),
          identity_params(%{
            "role" => "write",
            "workflow" => "release.yml",
            "covers_private" => "true",
            "covers_public" => "true"
          })
        )
        |> html_response(400)
        |> LazyHTML.from_document()

      assert document
             |> LazyHTML.query(~s(input[type="hidden"][name="workload_identity[covers_private]"]))
             |> LazyHTML.attribute("value") == ["false"]

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

  describe "the list of workload identities" do
    test "titles each workload identity by what it can do", %{
      admin: admin,
      organization: organization
    } do
      read = insert(:organization_workload_identity, organization: organization)

      private =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "release.yml"
        )

      public =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "release.yml",
          covers_private: false,
          packages: [],
          covers_public: true
        )

      both =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "release.yml",
          covers_public: true
        )

      document =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()

      title = fn identity ->
        document
        |> LazyHTML.query("#workload-identity-#{identity.id} > div > p")
        |> normalized_text()
      end

      assert title.(read) == "Fetch packages Read"
      assert title.(private) == "Publish private packages Write"
      assert title.(public) == "Publish public packages Write"
      assert title.(both) == "Publish private and public packages Write"

      assert document
             |> LazyHTML.query("#workload-identity-#{read.id} dd ul li")
             |> normalized_text() == "Fetch every package in #{organization.name}"
    end

    test "shows the repositories, workflow, environment and when it was added", %{
      admin: admin,
      organization: organization
    } do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          repositories: repositories(["acme/widget", "acme/gadget"]),
          workflow: "ci.yml",
          environment: "fetch"
        )

      text =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#workload-identity-#{identity.id}")
        |> normalized_text()

      assert text =~ "From acme/widget acme/gadget Workflow ci.yml · Environment fetch"
      assert text =~ "Added #{Calendar.strftime(identity.inserted_at, "%-d %b %Y")}"
    end

    test "folds the repositories past the fourth", %{admin: admin, organization: organization} do
      names = for name <- ~w(one two three four five six), do: "acme/#{name}"

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          repositories: repositories(names)
        )

      card =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#workload-identity-#{identity.id}")

      assert card |> LazyHTML.query("details summary") |> normalized_text() ==
               "acme/one acme/two acme/three acme/four and 2 more"

      assert card |> LazyHTML.query("details > div") |> normalized_text() == "acme/five acme/six"
    end

    test "notes the listed public packages the organization doesn't own", %{
      admin: admin,
      organization: organization
    } do
      insert(:package,
        name: "owned_one",
        package_owners: [build(:package_owner, user: organization.user, level: "full")]
      )

      insert(:package, name: "gone_one")

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "release.yml",
          covers_private: false,
          packages: [],
          covers_public: true,
          public_packages: ["gone_one", "owned_one"]
        )

      card =
        build_conn()
        |> test_login(admin)
        |> get(path(organization))
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#workload-identity-#{identity.id}")

      assert card |> LazyHTML.query("dd ul li s") |> normalized_text() == "gone_one"

      assert normalized_text(card) =~
               "#{organization.name} doesn't own gone_one, so this workload identity doesn't publish it."

      assert card |> LazyHTML.query("p strong") |> normalized_text() == "gone_one"
    end

    test "links Edit for admins with 2FA only", %{
      admin: admin,
      writer: writer,
      organization: organization
    } do
      identity = insert(:organization_workload_identity, organization: organization)
      edit = "#{path(organization)}/#{identity.id}/edit#workload-identity-form"

      assert build_conn()
             |> test_login(admin)
             |> get(path(organization))
             |> html_response(200) =~ ~s(href="#{edit}")

      refute build_conn()
             |> test_login(writer)
             |> get(path(organization))
             |> html_response(200) =~ "/edit"
    end
  end

  describe "GET /dashboard/orgs/:dashboard_org/workload-identities/:id/edit" do
    test "shows an admin the change form filled in", %{admin: admin, organization: organization} do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repository_owner: "acme",
          repositories: repositories(["acme/widget", "acme/gadget"]),
          workflow: "release.yml",
          environment: "release",
          packages: ["private_one"]
        )

      document =
        build_conn()
        |> test_login(admin)
        |> get("#{path(organization)}/#{identity.id}/edit")
        |> html_response(200)
        |> LazyHTML.from_document()

      form = LazyHTML.query(document, "#add-workload-identity-form")

      assert document |> LazyHTML.query("#workload-identity-form h2") |> normalized_text() ==
               "Change workload identity"

      assert LazyHTML.attribute(form, "action") == ["#{path(organization)}/#{identity.id}"]

      assert form |> LazyHTML.query(~s(input[name="_method"])) |> LazyHTML.attribute("value") ==
               ["put"]

      assert form |> LazyHTML.query("#workload-identity-role-read[disabled]") |> Enum.count() == 1

      assert form
             |> LazyHTML.query("#workload-identity-role-write[disabled][checked]")
             |> Enum.count() == 1

      assert form |> LazyHTML.query("#workload_identity_repository_owner") |> Enum.empty?()
      assert normalized_text(form) =~ "Repository owner acme"

      assert form |> LazyHTML.query("#workload_identity_repositories") |> LazyHTML.text() ==
               "widget\ngadget"

      assert form |> LazyHTML.query("#workload_identity_workflow") |> LazyHTML.attribute("value") ==
               ["release.yml"]

      assert form |> LazyHTML.query("#workload_identity_packages") |> LazyHTML.attribute("value") ==
               ["private_one"]

      assert form |> LazyHTML.query("#workload_identity_covers_private[checked]") |> Enum.count() ==
               1

      assert normalized_text(form) =~ "Cancel Save changes"
    end

    test "refuses a write member", %{writer: writer, organization: organization} do
      identity = insert(:organization_workload_identity, organization: organization)

      conn =
        build_conn()
        |> test_login(writer)
        |> get("#{path(organization)}/#{identity.id}/edit")

      assert html_response(conn, 400) =~ "You do not have permission for this action."
      refute conn.resp_body =~ "Change workload identity"
    end

    test "sends an admin without 2FA to enable it", %{organization: organization} do
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")
      identity = insert(:organization_workload_identity, organization: organization)

      conn =
        build_conn()
        |> test_login(admin)
        |> get("#{path(organization)}/#{identity.id}/edit")

      assert redirected_to(conn) == "/dashboard/security"
    end

    test "flashes not found for another organization's workload identity", %{
      admin: admin,
      organization: organization
    } do
      identity = insert(:organization_workload_identity)

      conn =
        build_conn()
        |> test_login(admin)
        |> get("#{path(organization)}/#{identity.id}/edit")

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end

    test "requires sudo", %{admin: admin, organization: organization} do
      identity = insert(:organization_workload_identity, organization: organization)

      conn =
        build_conn()
        |> test_login(admin, sudo: false)
        |> get("#{path(organization)}/#{identity.id}/edit")

      assert redirected_to(conn) =~ "/sudo"
    end
  end

  describe "the version in the change form" do
    test "is the version of the workload identity it changes", %{
      admin: admin,
      organization: organization
    } do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repository_owner: "acme",
          repositories: repositories(["acme/widget"]),
          workflow: "release.yml"
        )

      document =
        build_conn()
        |> test_login(admin)
        |> get("#{path(organization)}/#{identity.id}/edit")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert document
             |> LazyHTML.query(
               ~s(#add-workload-identity-form input[name="workload_identity[version]"])
             )
             |> LazyHTML.attribute("value") ==
               [WorkloadIdentities.version(Repo.get!(WorkloadIdentity, identity.id))]
    end
  end

  describe "PUT /dashboard/orgs/:dashboard_org/workload-identities/:id" do
    setup %{organization: organization} do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repository_owner: "acme",
          repository_owner_id: "11",
          repositories: [%TrustedRepository{name: "acme/widget", id: "22"}],
          workflow: "release.yml"
        )

      %{identity: identity}
    end

    defp stub_github(repositories) do
      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/" <> name, _, _ ->
        case Map.fetch(repositories, name) do
          {:ok, id} -> {:ok, 200, [], %{"id" => id, "owner" => %{"id" => 11}}}
          :error -> {:ok, 404, [], %{}}
        end
      end)
    end

    defp change_params(params) do
      %{
        "workload_identity" =>
          Map.merge(
            %{
              "repositories" => "widget",
              "workflow" => "release.yml",
              "environment" => "",
              "covers_private" => "true",
              "packages" => "",
              "covers_public" => "false"
            },
            params
          )
      }
    end

    test "changes the workload identity", %{
      admin: admin,
      organization: organization,
      identity: identity
    } do
      stub_github(%{"widget" => 22, "gadget" => 33})

      conn =
        build_conn()
        |> test_login(admin)
        |> put(
          "#{path(organization)}/#{identity.id}",
          change_params(%{"repositories" => "widget\ngadget", "packages" => "private_one"})
        )

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Workload identity saved."

      changed = Repo.get!(WorkloadIdentity, identity.id)
      assert changed.packages == ["private_one"]

      assert changed.repositories == [
               %TrustedRepository{name: "acme/widget", id: "22"},
               %TrustedRepository{name: "acme/gadget", id: "33"}
             ]

      assert Repo.get_by(AuditLog, action: "organization.workload_identity.update")
    end

    test "re-renders the change form with errors", %{
      admin: admin,
      organization: organization,
      identity: identity
    } do
      conn =
        build_conn()
        |> test_login(admin)
        |> put("#{path(organization)}/#{identity.id}", change_params(%{"workflow" => ""}))

      body = html_response(conn, 400)
      assert body =~ "is required for the write role"
      assert body =~ "Change workload identity"
      assert body =~ ~s(action="#{path(organization)}/#{identity.id}")
      assert Repo.get!(WorkloadIdentity, identity.id).workflow == "release.yml"
    end

    test "refuses a write member", %{
      writer: writer,
      organization: organization,
      identity: identity
    } do
      conn =
        build_conn()
        |> test_login(writer)
        |> put(
          "#{path(organization)}/#{identity.id}",
          change_params(%{"workflow" => "other.yml"})
        )

      assert conn.status == 400
      assert Repo.get!(WorkloadIdentity, identity.id).workflow == "release.yml"
    end

    test "requires 2FA on the admin's account", %{organization: organization, identity: identity} do
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")

      conn =
        build_conn()
        |> test_login(admin)
        |> put(
          "#{path(organization)}/#{identity.id}",
          change_params(%{"workflow" => "other.yml"})
        )

      assert redirected_to(conn) == "/dashboard/security"
      assert Repo.get!(WorkloadIdentity, identity.id).workflow == "release.yml"
    end

    test "flashes not found for another organization's workload identity", %{
      admin: admin,
      organization: organization
    } do
      other = insert(:organization_workload_identity)

      conn =
        build_conn()
        |> test_login(admin)
        |> put("#{path(organization)}/#{other.id}", change_params(%{}))

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end

    test "requires sudo", %{admin: admin, organization: organization, identity: identity} do
      conn =
        build_conn()
        |> test_login(admin, sudo: false)
        |> put(
          "#{path(organization)}/#{identity.id}",
          change_params(%{"workflow" => "other.yml"})
        )

      assert redirected_to(conn) =~ "/sudo"
      assert Repo.get!(WorkloadIdentity, identity.id).workflow == "release.yml"
    end

    test "refuses once the lookup limit is reached and says change", %{
      admin: admin,
      organization: organization,
      identity: identity
    } do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
      on_exit(fn -> PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage) end)
      align_to_throttle_bucket(60 * 60_000)
      for _ <- 1..20, do: HexpmWeb.Plugs.Attack.workload_identity_lookup_throttle(admin.id)

      conn =
        build_conn()
        |> test_login(admin)
        |> put(
          "#{path(organization)}/#{identity.id}",
          change_params(%{"workflow" => "other.yml"})
        )

      assert redirected_to(conn) == path(organization)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Too many attempts to change a workload identity in the last hour. Try again later."
    end

    test "sends the admin back to the form when it changed since the form was loaded", %{
      admin: admin,
      organization: organization,
      identity: identity
    } do
      version = WorkloadIdentities.version(Repo.get!(WorkloadIdentity, identity.id))

      identity
      |> Ecto.Changeset.change(workflow: "other.yml")
      |> Repo.update!()

      conn =
        build_conn()
        |> test_login(admin)
        |> put(
          "#{path(organization)}/#{identity.id}",
          change_params(%{"workflow" => "publish.yml", "version" => version})
        )

      assert redirected_to(conn) == "#{path(organization)}/#{identity.id}/edit"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Someone else changed the workload identity while you were editing it. " <>
                 "Review it and save again."

      assert Repo.get!(WorkloadIdentity, identity.id).workflow == "other.yml"
      refute Repo.get_by(AuditLog, action: "organization.workload_identity.update")
    end

    test "sends the admin back to the form when someone else changed it meanwhile", %{
      admin: admin,
      organization: organization,
      identity: identity
    } do
      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        identity
        |> Ecto.Changeset.change(workflow: "other.yml")
        |> Repo.update!()

        {:ok, 200, [], %{"id" => 33, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> put(
          "#{path(organization)}/#{identity.id}",
          change_params(%{"repositories" => "widget\ngadget"})
        )

      assert redirected_to(conn) == "#{path(organization)}/#{identity.id}/edit"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Someone else changed the workload identity while you were editing it. " <>
                 "Review it and save again."

      changed = Repo.get!(WorkloadIdentity, identity.id)
      assert changed.workflow == "other.yml"
      assert changed.repositories == [%TrustedRepository{name: "acme/widget", id: "22"}]
      refute Repo.get_by(AuditLog, action: "organization.workload_identity.update")
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

  describe "GitHub call limit" do
    setup do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
      on_exit(fn -> PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage) end)
      align_to_throttle_bucket(60 * 60_000)
      :ok
    end

    test "refuses an add before asking GitHub once its calls would pass the limit", %{
      admin: admin,
      organization: organization
    } do
      HexpmWeb.Plugs.Attack.workload_identity_github_throttle(admin.id, 100)
      expect(Hexpm.HTTP.Mock, :get, 0, fn _url, _headers, _opts -> flunk("asked GitHub") end)

      conn =
        build_conn()
        |> test_login(admin)
        |> post(path(organization), identity_params(%{"role" => "read"}))

      assert redirected_to(conn) == path(organization)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Too many attempts to add a workload identity in the last hour. Try again later."

      assert WorkloadIdentities.list(organization) == []
    end

    test "changes a workload identity without GitHub calls once the call limit is used up", %{
      admin: admin,
      organization: organization
    } do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repository_owner: "acme",
          repository_owner_id: "11",
          repositories: [%TrustedRepository{name: "acme/widget", id: "22"}],
          workflow: "release.yml"
        )

      HexpmWeb.Plugs.Attack.workload_identity_github_throttle(admin.id, 100)
      expect(Hexpm.HTTP.Mock, :get, 0, fn _url, _headers, _opts -> flunk("asked GitHub") end)

      conn =
        build_conn()
        |> test_login(admin)
        |> put("#{path(organization)}/#{identity.id}", %{
          "workload_identity" => %{
            "repositories" => "widget",
            "workflow" => "publish.yml",
            "covers_private" => "true",
            "covers_public" => "false"
          }
        })

      assert redirected_to(conn) == path(organization)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Workload identity saved."
      assert Repo.get!(WorkloadIdentity, identity.id).workflow == "publish.yml"
    end
  end

  describe "changing a workload identity without active billing" do
    setup %{organization: organization} do
      organization =
        organization
        |> Ecto.Changeset.change(billing_active: false, trial_end: nil)
        |> Repo.update!()

      %{organization: organization}
    end

    test "keeps the private packages of a write workload identity", %{
      admin: admin,
      organization: organization
    } do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repository_owner: "acme",
          repository_owner_id: "11",
          repositories: [%TrustedRepository{name: "acme/widget", id: "22"}],
          workflow: "release.yml",
          covers_private: true,
          packages: ["private_one"]
        )

      document =
        build_conn()
        |> test_login(admin)
        |> get("#{path(organization)}/#{identity.id}/edit")
        |> html_response(200)
        |> LazyHTML.from_document()

      checkbox = LazyHTML.query(document, "#workload_identity_covers_private")
      assert LazyHTML.attribute(checkbox, "checked") != []
      assert LazyHTML.attribute(checkbox, "disabled") != []

      assert document
             |> LazyHTML.query(~s(input[type="hidden"][name="workload_identity[covers_private]"]))
             |> LazyHTML.attribute("value") == ["true"]

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        {:ok, 200, [], %{"id" => 33, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(admin)
        |> put("#{path(organization)}/#{identity.id}", %{
          "workload_identity" => %{
            "repositories" => "widget\ngadget",
            "workflow" => "release.yml",
            "environment" => "",
            "covers_private" => "true",
            "packages" => "private_one",
            "covers_public" => "false"
          }
        })

      assert redirected_to(conn) == path(organization)

      changed = Repo.get!(WorkloadIdentity, identity.id)
      assert changed.covers_private == true
      assert changed.packages == ["private_one"]

      assert changed.repositories == [
               %TrustedRepository{name: "acme/widget", id: "22"},
               %TrustedRepository{name: "acme/gadget", id: "33"}
             ]
    end

    test "changes a read workload identity", %{admin: admin, organization: organization} do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "read",
          repository_owner: "acme",
          repository_owner_id: "11",
          repositories: [%TrustedRepository{name: "acme/widget", id: "22"}],
          workflow: ""
        )

      build_conn()
      |> test_login(admin)
      |> get("#{path(organization)}/#{identity.id}/edit")
      |> html_response(200)

      conn =
        build_conn()
        |> test_login(admin)
        |> put("#{path(organization)}/#{identity.id}", %{
          "workload_identity" => %{
            "repositories" => "widget",
            "workflow" => "ci.yml",
            "environment" => "",
            "covers_private" => "false",
            "covers_public" => "false"
          }
        })

      assert redirected_to(conn) == path(organization)
      assert Repo.get!(WorkloadIdentity, identity.id).workflow == "ci.yml"
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

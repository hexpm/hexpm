defmodule HexpmWeb.PackageWorkloadIdentityControllerTest do
  use HexpmWeb.ConnCase, async: false

  import Mox

  alias Hexpm.WorkloadIdentities
  alias Hexpm.WorkloadIdentities.TrustedRepository

  setup :verify_on_exit!

  setup do
    full_owner = insert(:user_with_tfa)
    maintainer = insert(:user)
    non_owner = insert(:user)

    package =
      insert(:package,
        package_owners: [
          build(:package_owner, user: full_owner, level: "full"),
          build(:package_owner, user: maintainer, level: "maintainer")
        ]
      )

    package = Hexpm.Repo.preload(package, :repository)
    %{full_owner: full_owner, maintainer: maintainer, non_owner: non_owner, package: package}
  end

  defp repositories(names) do
    names
    |> Enum.with_index(1)
    |> Enum.map(fn {name, index} -> %TrustedRepository{name: name, id: "#{index}#{index}"} end)
  end

  defp normalized_text(node),
    do: node |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  defp settings_nav(document) do
    document
    |> LazyHTML.query("#package-settings-nav a")
    |> Enum.map(fn link ->
      {link |> LazyHTML.text(separator: " ") |> String.replace(~r/\s+/, " ") |> String.trim(),
       link |> LazyHTML.attribute("aria-current") |> List.first()}
    end)
  end

  describe "GET /packages/:name/workload-identities" do
    test "full owner with 2FA and sudo sees the page", %{
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")

      assert html_response(conn, 200) =~ "Workload identities"
    end

    test "selects Workload identities in the settings nav", %{
      full_owner: full_owner,
      package: package
    } do
      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert settings_nav(document) == [
               {"Owners", nil},
               {"Publish approval NEW", nil},
               {"Workload identities", "page"}
             ]
    end

    test "leaves Workload identities out of the settings nav when the feature is off", %{
      full_owner: full_owner,
      package: package
    } do
      put_feature_flag(:workload_identity, mode: :off)

      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/owners")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert settings_nav(document) == [{"Owners", "page"}]
    end

    test "lists existing workload identities", %{full_owner: full_owner, package: package} do
      insert(:workload_identity, package: package, repositories: repositories(["acme/widget"]))

      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")

      assert html_response(conn, 200) =~ "acme/widget"
    end

    test "lists the organization workload identities that publish a public package", %{
      full_owner: full_owner,
      package: package
    } do
      organization = insert(:organization)
      insert(:package_owner, package: package, user: organization.user, level: "full")

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/widget"]),
        workflow: "release.yml",
        environment: "release",
        covers_public: true
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/gadget"]),
        workflow: "private.yml"
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/listed"]),
        workflow: "listed.yml",
        covers_public: true,
        public_packages: [package.name, "secret_other_package"]
      )

      body =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)

      document = LazyHTML.from_document(body)
      cards = LazyHTML.query(document, ~s(li[id^="organization-workload-identity-"]))
      assert Enum.count(cards) == 2

      card = fn repository ->
        cards |> Enum.find(&(LazyHTML.text(&1) =~ repository)) |> normalized_text()
      end

      assert card.("acme/widget") =~ "Publish #{package.name} Organization #{organization.name}"
      assert card.("acme/widget") =~ "Manage on #{organization.name}'s page"
      assert card.("acme/widget") =~ "Workflow release.yml · Environment release"

      assert card.("acme/widget") =~
               "Publishes #{package.name} while #{organization.name} owns it."

      assert card.("acme/listed") =~ "Workflow listed.yml · Environment any"
      assert body =~ ~s(href="/orgs/#{organization.name}")
      assert body =~ ~s(href="/dashboard/orgs/#{organization.name}/workload-identities")
      assert body =~ "first release is published with a user account or a key"
      refute body =~ "acme/gadget"
      refute body =~ "secret_other_package"
    end

    test "leaves out organization workload identities of an organization that only maintains it",
         %{full_owner: full_owner, package: package} do
      organization = insert(:organization)
      insert(:package_owner, package: package, user: organization.user, level: "maintainer")

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/widget"]),
        workflow: "release.yml",
        covers_public: true
      )

      body =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)

      refute body =~ "organization-workload-identity-"
      refute body =~ "acme/widget"
    end

    test "leaves out organization workload identities of organizations without the feature flag",
         %{full_owner: full_owner, package: package} do
      organization = insert(:organization)
      insert(:package_owner, package: package, user: organization.user, level: "full")

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/widget"]),
        workflow: "release.yml",
        covers_public: true
      )

      flags = Application.fetch_env!(:hexpm, :feature_flags)
      on_exit(fn -> Application.put_env(:hexpm, :feature_flags, flags) end)

      Application.put_env(
        :hexpm,
        :feature_flags,
        Keyword.put(flags, :workload_identity, mode: :beta, beta_users: [full_owner.username])
      )

      body =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)

      refute body =~ "organization-workload-identity-"
      refute body =~ "acme/widget"
    end

    test "leaves out organization workload identities once the organization stops owning it", %{
      full_owner: full_owner,
      package: package
    } do
      organization = insert(:organization)

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/widget"]),
        workflow: "release.yml",
        covers_public: true
      )

      body =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)

      refute body =~ "organization-workload-identity-"
      refute body =~ "acme/widget"
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> get("/packages/#{package.name}/workload-identities")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "shows a full owner without two-factor authentication the page without the controls", %{
      package: package
    } do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")
      insert(:workload_identity, package: package, repositories: repositories(["acme/widget"]))

      document =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert LazyHTML.text(document) =~ "acme/widget"

      assert LazyHTML.text(document) =~
               "Two-factor authentication is required to add, change and remove workload identities."

      refute LazyHTML.text(document) =~ "Only full owners and organization admins"
      assert document |> LazyHTML.query("#add-workload-identity-form") |> Enum.empty?()

      assert document
             |> LazyHTML.query(~s(form[id^="remove-workload-identity-form-"]))
             |> Enum.empty?()
    end

    test "shows a maintainer the workload identities without the controls", %{
      maintainer: maintainer,
      package: package
    } do
      insert(:workload_identity, package: package, repositories: repositories(["acme/widget"]))

      document =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert LazyHTML.text(document) =~ "acme/widget"

      assert LazyHTML.text(document) =~
               "Only full owners and organization admins can add, change and remove workload identities."

      assert document |> LazyHTML.query("#add-workload-identity-form") |> Enum.empty?()

      assert document
             |> LazyHTML.query(~s(form[id^="remove-workload-identity-form-"]))
             |> Enum.empty?()
    end

    test "non-owner is forbidden", %{non_owner: non_owner, package: package} do
      conn =
        build_conn()
        |> test_login(non_owner)
        |> get("/packages/#{package.name}/workload-identities")

      assert conn.status == 403
    end

    test "requires login", %{package: package} do
      conn = get(build_conn(), "/packages/#{package.name}/workload-identities")
      assert redirected_to(conn) =~ "/login"
    end

    test "returns 404 when the feature flag is disabled", %{
      full_owner: full_owner,
      package: package
    } do
      put_feature_flag(:workload_identity, mode: :off)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")

      assert conn.status == 404
    end

    test "shows the page in beta when any owner is on the user list", %{
      full_owner: full_owner,
      maintainer: maintainer,
      package: package
    } do
      put_feature_flag(:workload_identity,
        mode: :beta,
        beta_users: [maintainer.username],
        beta_organizations: []
      )

      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert settings_nav(document) == [
               {"Owners", nil},
               {"Publish approval NEW", nil},
               {"Workload identities", "page"}
             ]
    end

    test "returns 404 and leaves out the settings nav entry in beta when no owner is listed", %{
      full_owner: full_owner,
      non_owner: non_owner,
      package: package
    } do
      put_feature_flag(:workload_identity,
        mode: :beta,
        beta_users: [non_owner.username],
        beta_organizations: []
      )

      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")

      assert conn.status == 404

      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/owners")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert settings_nav(document) == [{"Owners", "page"}]
    end
  end

  describe "POST /packages/:name/workload-identities" do
    test "creates a workload identity after resolving GitHub ids", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "added"

      assert [workload_identity] = WorkloadIdentities.list(package)
      assert workload_identity.repositories == [%TrustedRepository{name: "acme/widget", id: "22"}]
      assert workload_identity.repository_owner_id == "11"
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) =~ "/sudo"
    end

    test "refuses a full owner without two-factor authentication", %{package: package} do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")

      conn =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert conn.status == 403
      assert WorkloadIdentities.list(package) == []
    end

    test "rejects a duplicate workload identity config with a 400 and shows the changeset error",
         %{
           full_owner: full_owner,
           package: package
         } do
      insert(:workload_identity,
        package: package,
        repository_owner: "acme",
        repositories: [%TrustedRepository{name: "acme/widget", id: "22"}],
        workflow: "release.yml",
        environment: ""
      )

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert html_response(conn, 400) =~
               "already have a workload identity with this workflow and environment"
    end

    test "shows the changeset error for an invalid workflow", %{
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release"
          }
        })

      body = html_response(conn, 400)
      assert body =~ "has invalid format"

      assert body
             |> LazyHTML.from_document()
             |> LazyHTML.query("#workload_identity_repositories")
             |> LazyHTML.text()
             |> String.trim() == "widget"

      refute body =~ "acme/widget"
    end

    test "flashes an error when GitHub repository resolution fails", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/missing/widget", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/missing", _, _ ->
        {:ok, 404, [], %{}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "missing",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "could not be resolved"
      assert WorkloadIdentities.list(package) == []
    end

    test "shows a changeset error for a public repository without an environment", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}, "visibility" => "public"}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "publish.yml"
          }
        })

      body = html_response(conn, 400)
      assert body =~ "is required because acme/widget is public"
      assert body =~ ~s(value="publish.yml")

      assert body
             |> LazyHTML.from_document()
             |> LazyHTML.query("#workload_identity_repositories")
             |> LazyHTML.text()
             |> String.trim() == "widget"

      assert WorkloadIdentities.list(package) == []
    end

    test "creates a workload identity for a repository Hex cannot see when given its id", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 11}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "private 22",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"

      assert [
               %{
                 repository_owner_id: "11",
                 repositories: [%TrustedRepository{name: "acme/private", id: "22"}]
               }
             ] = WorkloadIdentities.list(package)
    end

    test "shows a changeset error for a repository Hex cannot see without its id", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 11}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "private",
            "workflow" => "release.yml"
          }
        })

      assert html_response(conn, 400) =~
               "acme/private needs its repository ID after the name, because Hex can&#39;t see it on GitHub"

      assert WorkloadIdentities.list(package) == []
    end

    test "prefers the resolved repository id over a supplied one", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget 99",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"

      assert [%{repositories: [%TrustedRepository{id: "22"}]}] =
               WorkloadIdentities.list(package)
    end

    test "flashes an error when GitHub answers with a server error", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 500, [], %{}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "try again later"
      assert WorkloadIdentities.list(package) == []
    end

    test "flashes an error when GitHub cannot be reached", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:error, :timeout}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "try again later"
      assert WorkloadIdentities.list(package) == []
    end

    test "is forbidden for maintainer even with sudo", %{
      maintainer: maintainer,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(maintainer, sudo: true)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert conn.status == 403
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
      full_owner: full_owner,
      package: package
    } do
      for _ <- 1..20, do: HexpmWeb.Plugs.Attack.workload_identity_lookup_throttle(full_owner.id)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      assert WorkloadIdentities.list(package) == []
    end
  end

  describe "the list for a manager" do
    test "shows each workload identity with its repositories and Edit and Remove", %{
      full_owner: full_owner,
      package: package
    } do
      workload_identity =
        insert(:workload_identity,
          package: package,
          repositories: repositories(["acme/widget", "acme/gadget"]),
          workflow: "release.yml",
          environment: "release"
        )

      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)
        |> LazyHTML.from_document()

      card = LazyHTML.query(document, "#workload-identity-#{workload_identity.id}")

      assert normalized_text(card) =~
               "Publish #{package.name} Package Edit acme/widget acme/gadget " <>
                 "Workflow release.yml · Environment release"

      assert normalized_text(card) =~
               "Added #{Calendar.strftime(workload_identity.inserted_at, "%-d %b %Y")}"

      assert card
             |> LazyHTML.query("a[href]")
             |> LazyHTML.attribute("href") == [
               "/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit#workload-identity-form"
             ]

      assert document
             |> LazyHTML.query("#remove-workload-identity-form-#{workload_identity.id}")
             |> Enum.count() == 1
    end

    test "leaves out Edit for a maintainer", %{maintainer: maintainer, package: package} do
      workload_identity = insert(:workload_identity, package: package)

      body =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)

      refute body =~ "/workload-identities/#{workload_identity.id}/edit"
    end
  end

  describe "GET /packages/:name/workload-identities/:id/edit" do
    test "carries the version of the workload identity it changes", %{
      full_owner: full_owner,
      package: package
    } do
      workload_identity =
        insert(:workload_identity,
          package: package,
          repository_owner: "acme",
          repositories: repositories(["acme/widget"]),
          workflow: "release.yml"
        )

      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit")
        |> html_response(200)
        |> LazyHTML.from_document()

      version =
        WorkloadIdentities.version(
          Hexpm.Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
        )

      assert document
             |> LazyHTML.query(
               ~s(#add-workload-identity-form input[name="workload_identity[version]"])
             )
             |> LazyHTML.attribute("value") == [version]
    end

    test "shows a full owner the change form filled in", %{
      full_owner: full_owner,
      package: package
    } do
      workload_identity =
        insert(:workload_identity,
          package: package,
          repository_owner: "acme",
          repositories: repositories(["acme/widget", "acme/gadget"]),
          workflow: "release.yml",
          environment: "release"
        )

      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit")
        |> html_response(200)
        |> LazyHTML.from_document()

      form = LazyHTML.query(document, "#add-workload-identity-form")
      path = "/packages/#{package.name}/workload-identities/#{workload_identity.id}"

      assert normalized_text(document) =~ "Change workload identity"
      assert LazyHTML.attribute(form, "action") == [path]

      assert form |> LazyHTML.query(~s(input[name="_method"])) |> LazyHTML.attribute("value") ==
               ["put"]

      assert form |> LazyHTML.query("#workload_identity_repository_owner") |> Enum.empty?()
      assert normalized_text(form) =~ "Repository owner acme"

      assert form |> LazyHTML.query("#workload_identity_repositories") |> LazyHTML.text() ==
               "widget\ngadget"

      assert form |> LazyHTML.query("#workload_identity_workflow") |> LazyHTML.attribute("value") ==
               ["release.yml"]

      assert form
             |> LazyHTML.query("#workload_identity_environment")
             |> LazyHTML.attribute("value") == ["release"]

      assert normalized_text(form) =~ "Cancel Save changes"
    end

    test "is forbidden for a maintainer", %{maintainer: maintainer, package: package} do
      workload_identity = insert(:workload_identity, package: package)

      conn =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit")

      assert conn.status == 403
    end

    test "refuses a full owner without two-factor authentication", %{package: package} do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")
      workload_identity = insert(:workload_identity, package: package)

      conn =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> get("/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit")

      assert conn.status == 403
    end

    test "returns 404 for an unknown id or another package's", %{
      full_owner: full_owner,
      package: package
    } do
      other =
        insert(:package, package_owners: [build(:package_owner, user: full_owner, level: "full")])

      workload_identity = insert(:workload_identity, package: other)
      conn = test_login(build_conn(), full_owner)

      assert get(conn, "/packages/#{package.name}/workload-identities/999999/edit").status == 404

      assert get(
               conn,
               "/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit"
             ).status == 404
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      workload_identity = insert(:workload_identity, package: package)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> get("/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit")

      assert redirected_to(conn) =~ "/sudo"
    end
  end

  describe "PUT /packages/:name/workload-identities/:id" do
    setup %{package: package} do
      workload_identity =
        insert(:workload_identity,
          package: package,
          repository_owner: "acme",
          repository_owner_id: "11",
          repositories: [%TrustedRepository{name: "acme/widget", id: "22"}],
          workflow: "release.yml"
        )

      %{workload_identity: workload_identity}
    end

    defp stub_github(repositories) do
      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/" <> name, _, _ ->
        case Map.fetch(repositories, name) do
          {:ok, id} -> {:ok, 200, [], %{"id" => id, "owner" => %{"id" => 11}}}
          :error -> {:ok, 404, [], %{}}
        end
      end)
    end

    test "changes the repositories and the workflow", %{
      full_owner: full_owner,
      package: package,
      workload_identity: workload_identity
    } do
      stub_github(%{"widget" => 22, "gadget" => 33})

      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{
            "repositories" => "widget\ngadget",
            "workflow" => "publish.yml",
            "environment" => ""
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Workload identity saved."

      assert [changed] = WorkloadIdentities.list(package)
      assert changed.workflow == "publish.yml"

      assert changed.repositories == [
               %TrustedRepository{name: "acme/widget", id: "22"},
               %TrustedRepository{name: "acme/gadget", id: "33"}
             ]
    end

    test "re-renders the change form with errors", %{
      full_owner: full_owner,
      package: package,
      workload_identity: workload_identity
    } do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{"repositories" => "widget", "workflow" => "release"}
        })

      body = html_response(conn, 400)
      assert body =~ "has invalid format"
      assert body =~ "Change workload identity"

      assert body =~
               ~s(action="/packages/#{package.name}/workload-identities/#{workload_identity.id}")

      assert [%{workflow: "release.yml"}] = WorkloadIdentities.list(package)
    end

    test "says which repository was renamed or transferred", %{
      full_owner: full_owner,
      package: package,
      workload_identity: workload_identity
    } do
      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        {:ok, 301, [], %{}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{
            "repositories" => "widget\ngadget",
            "workflow" => "release.yml"
          }
        })

      assert html_response(conn, 400) =~
               "acme/gadget was renamed or transferred on GitHub. " <>
                 "Replace it with the repository&#39;s new name"

      assert [%{repositories: [%{name: "acme/widget"}]}] = WorkloadIdentities.list(package)
    end

    test "sends the owner back to the form when it changed since the form was loaded", %{
      full_owner: full_owner,
      package: package,
      workload_identity: workload_identity
    } do
      version =
        WorkloadIdentities.version(
          Hexpm.Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
        )

      workload_identity
      |> Ecto.Changeset.change(workflow: "other.yml")
      |> Hexpm.Repo.update!()

      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{
            "repositories" => "widget",
            "workflow" => "publish.yml",
            "version" => version
          }
        })

      assert redirected_to(conn) ==
               "/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Someone else changed the workload identity while you were editing it. " <>
                 "Review it and save again."

      assert [%{workflow: "other.yml"}] = WorkloadIdentities.list(package)
    end

    test "sends the owner back to the form when someone else changed it meanwhile", %{
      full_owner: full_owner,
      package: package,
      workload_identity: workload_identity
    } do
      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        workload_identity
        |> Ecto.Changeset.change(workflow: "other.yml")
        |> Hexpm.Repo.update!()

        {:ok, 200, [], %{"id" => 33, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{
            "repositories" => "widget\ngadget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) ==
               "/packages/#{package.name}/workload-identities/#{workload_identity.id}/edit"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Someone else changed the workload identity while you were editing it. " <>
                 "Review it and save again."

      assert [%{workflow: "other.yml", repositories: [%{name: "acme/widget"}]}] =
               WorkloadIdentities.list(package)
    end

    test "returns 404 for another package's workload identity", %{
      full_owner: full_owner,
      package: package
    } do
      other = insert(:workload_identity)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/#{other.id}", %{
          "workload_identity" => %{"repositories" => "widget", "workflow" => "release.yml"}
        })

      assert response(conn, 404)

      assert Hexpm.Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, other.id).workflow ==
               other.workflow
    end

    test "is forbidden for a maintainer", %{
      maintainer: maintainer,
      package: package,
      workload_identity: workload_identity
    } do
      conn =
        build_conn()
        |> test_login(maintainer)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{"repositories" => "widget", "workflow" => "publish.yml"}
        })

      assert conn.status == 403
      assert [%{workflow: "release.yml"}] = WorkloadIdentities.list(package)
    end

    test "refuses a full owner without two-factor authentication", %{
      package: package,
      workload_identity: workload_identity
    } do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")

      conn =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{"repositories" => "widget", "workflow" => "publish.yml"}
        })

      assert conn.status == 403
      assert [%{workflow: "release.yml"}] = WorkloadIdentities.list(package)
    end

    test "returns 404 for an unknown id", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/999999", %{
          "workload_identity" => %{"repositories" => "widget", "workflow" => "publish.yml"}
        })

      assert conn.status == 404
    end

    test "redirects to /sudo when no sudo mode", %{
      full_owner: full_owner,
      package: package,
      workload_identity: workload_identity
    } do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{"repositories" => "widget", "workflow" => "publish.yml"}
        })

      assert redirected_to(conn) =~ "/sudo"
      assert [%{workflow: "release.yml"}] = WorkloadIdentities.list(package)
    end

    test "refuses once the lookup limit is reached and says change", %{
      full_owner: full_owner,
      package: package,
      workload_identity: workload_identity
    } do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
      on_exit(fn -> PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage) end)
      align_to_throttle_bucket(60 * 60_000)
      for _ <- 1..20, do: HexpmWeb.Plugs.Attack.workload_identity_lookup_throttle(full_owner.id)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> put("/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{"repositories" => "widget", "workflow" => "publish.yml"}
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Too many attempts to change a workload identity in the last hour. Try again later."
    end
  end

  describe "DELETE /packages/:name/workload-identities/:id" do
    test "full owner with sudo removes a workload identity", %{
      full_owner: full_owner,
      package: package
    } do
      workload_identity = insert(:workload_identity, package: package)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/workload-identities/#{workload_identity.id}")

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "removed"
      assert WorkloadIdentities.get(package, workload_identity.id) == nil
    end

    test "returns 404 for unknown id", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/workload-identities/999999")

      assert conn.status == 404
    end

    test "returns 404 for cross-package id", %{full_owner: full_owner, package: package} do
      other =
        insert(:package, package_owners: [build(:package_owner, user: full_owner, level: "full")])

      workload_identity = insert(:workload_identity, package: other)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/workload-identities/#{workload_identity.id}")

      assert conn.status == 404
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      workload_identity = insert(:workload_identity, package: package)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> delete("/packages/#{package.name}/workload-identities/#{workload_identity.id}")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "refuses a full owner without two-factor authentication", %{package: package} do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")
      workload_identity = insert(:workload_identity, package: package)

      conn =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> delete("/packages/#{package.name}/workload-identities/#{workload_identity.id}")

      assert conn.status == 403
      assert WorkloadIdentities.get(package, workload_identity.id)
    end

    test "is forbidden for maintainer even with sudo", %{
      maintainer: maintainer,
      package: package
    } do
      workload_identity = insert(:workload_identity, package: package)

      conn =
        build_conn()
        |> test_login(maintainer, sudo: true)
        |> delete("/packages/#{package.name}/workload-identities/#{workload_identity.id}")

      assert conn.status == 403
    end
  end

  describe "a public package an organization owns" do
    setup do
      organization = insert(:organization)
      insert(:repository, organization: organization, name: organization.name)

      package =
        insert(:package,
          repository_id: 1,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )

      workload_identity =
        insert(:workload_identity,
          package: package,
          repositories: repositories(["acme/widget"]),
          workflow: "release.yml"
        )

      %{organization: organization, package: package, workload_identity: workload_identity}
    end

    test "shows a member without 2FA the workload identities without the controls", %{
      organization: organization,
      package: package
    } do
      member = insert(:user)
      insert(:organization_user, organization: organization, user: member, role: "read")

      document =
        build_conn()
        |> test_login(member)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert normalized_text(document) =~ "acme/widget Workflow release.yml"

      assert LazyHTML.text(document) =~
               "Only full owners and organization admins can add, change and remove workload identities."

      assert document |> LazyHTML.query("#add-workload-identity-form") |> Enum.empty?()

      assert document
             |> LazyHTML.query(~s(form[id^="remove-workload-identity-form-"]))
             |> Enum.empty?()

      assert settings_nav(document) == [
               {"Owners", nil},
               {"Publish approval NEW", nil},
               {"Workload identities", "page"}
             ]
    end

    test "shows an admin the controls", %{organization: organization, package: package} do
      admin = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: admin, role: "admin")

      document =
        build_conn()
        |> test_login(admin)
        |> get("/packages/#{package.name}/workload-identities")
        |> html_response(200)
        |> LazyHTML.from_document()

      refute LazyHTML.text(document) =~ "Only full owners and organization admins"
      refute document |> LazyHTML.query("#add-workload-identity-form") |> Enum.empty?()

      refute document
             |> LazyHTML.query(~s(form[id^="remove-workload-identity-form-"]))
             |> Enum.empty?()
    end

    test "refuses a member's changes", %{
      organization: organization,
      package: package,
      workload_identity: workload_identity
    } do
      member = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: member, role: "write")
      conn = test_login(build_conn(), member, sudo: true)

      added =
        post(conn, "/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "other",
            "workflow" => "release.yml"
          }
        })

      changed =
        put(conn, "/packages/#{package.name}/workload-identities/#{workload_identity.id}", %{
          "workload_identity" => %{"repositories" => "other", "workflow" => "other.yml"}
        })

      removed =
        delete(conn, "/packages/#{package.name}/workload-identities/#{workload_identity.id}")

      assert added.status == 403
      assert changed.status == 403
      assert removed.status == 403
      assert [%{id: id}] = WorkloadIdentities.list(package)
      assert id == workload_identity.id
    end
  end

  describe "private package" do
    setup do
      org_user = insert(:user_with_tfa)
      organization = insert(:organization, user: org_user)
      insert(:organization_user, organization: organization, user: org_user, role: "admin")
      repository = insert(:repository, organization: organization)

      package =
        insert(:package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: org_user, level: "full")]
        )

      package = Hexpm.Repo.preload(package, :repository)

      %{organization: organization, repository: repository, org_user: org_user, package: package}
    end

    test "refuses a package workload identity and points to the organization page", %{
      org_user: org_user,
      repository: repository,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(org_user, sudo: true)
        |> post("/packages/#{repository.name}/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repositories" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/dashboard/orgs/#{repository.name}/workload-identities"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "managed on the organization's Workload identities page"

      assert WorkloadIdentities.list(package) == []
    end
  end

  describe "private repository routes" do
    setup do
      org_user = insert(:user_with_tfa)
      organization = insert(:organization, user: org_user)
      repository = insert(:repository, organization: organization)

      full_owner = insert(:user_with_tfa)
      insert(:organization_user, organization: organization, user: full_owner, role: "admin")

      package =
        insert(:package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: full_owner, level: "full")]
        )

      package = Hexpm.Repo.preload(package, :repository)

      %{
        organization: organization,
        repository: repository,
        full_owner: full_owner,
        package: package
      }
    end

    test "full owner can view management page on private repo", %{
      repository: repository,
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{repository.name}/#{package.name}/workload-identities")

      assert html_response(conn, 200) =~ "Workload identities"
    end

    test "lists the organization workload identities that can publish the package", %{
      organization: organization,
      repository: repository,
      full_owner: full_owner,
      package: package
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/covering"]),
        workflow: "release.yml"
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/excluded"]),
        workflow: "release.yml",
        packages: ["other"]
      )

      insert(:organization_workload_identity,
        organization: organization,
        repositories: repositories(["acme/fetching"])
      )

      body =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{repository.name}/#{package.name}/workload-identities")
        |> html_response(200)

      assert body =~ "published by the organization's workload identities"

      assert body
             |> LazyHTML.from_document()
             |> LazyHTML.query(~s(li[id^="organization-workload-identity-"]))
             |> normalized_text() =~ "Publish #{package.name} acme/covering Workflow release.yml"

      refute body =~ "add-workload-identity-form"
      assert body =~ "/dashboard/orgs/#{repository.name}/workload-identities"
      refute body =~ "acme/excluded"
      refute body =~ "acme/fetching"
    end

    test "answers an outsider the same for a package that exists and one that does not", %{
      repository: repository,
      package: package
    } do
      outsider = insert(:user)

      existing =
        build_conn()
        |> test_login(outsider)
        |> get("/packages/#{repository.name}/#{package.name}/workload-identities")

      missing =
        build_conn()
        |> test_login(outsider)
        |> get("/packages/#{repository.name}/no-such-package/workload-identities")

      assert existing.status == 404
      assert missing.status == 404
    end

    test "shows a member who is not an owner the organization workload identities", %{
      organization: organization,
      repository: repository,
      package: package
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: repositories(["acme/covering"]),
        workflow: "release.yml"
      )

      member = insert(:user)
      insert(:organization_user, organization: organization, user: member, role: "read")

      body =
        build_conn()
        |> test_login(member)
        |> get("/packages/#{repository.name}/#{package.name}/workload-identities")
        |> html_response(200)

      assert normalized_text(LazyHTML.from_document(body)) =~ "acme/covering Workflow release.yml"
      assert body =~ "/dashboard/orgs/#{repository.name}/workload-identities"
    end
  end
end

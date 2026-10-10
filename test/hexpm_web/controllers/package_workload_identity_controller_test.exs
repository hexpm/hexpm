defmodule HexpmWeb.PackageWorkloadIdentityControllerTest do
  use HexpmWeb.ConnCase, async: false

  import Mox

  alias Hexpm.WorkloadIdentities

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

  defp settings_nav(document) do
    document
    |> LazyHTML.query("#package-settings-nav a")
    |> Enum.map(fn link ->
      {link |> LazyHTML.text(separator: " ") |> String.trim(),
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
               {"Workload identities", "page"}
             ]
    end

    test "leaves Workload identities out of the settings nav when the feature is off", %{
      full_owner: full_owner,
      package: package
    } do
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, workload_identity: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

      document =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/owners")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert settings_nav(document) == [{"Owners", "page"}]
    end

    test "lists existing workload identities", %{full_owner: full_owner, package: package} do
      insert(:workload_identity, package: package, repository: "acme/widget")

      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")

      assert html_response(conn, 200) =~ "acme/widget"
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> get("/packages/#{package.name}/workload-identities")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "refuses a full owner without two-factor authentication", %{package: package} do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")

      conn =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> get("/packages/#{package.name}/workload-identities")

      assert conn.status == 403
      assert conn.resp_body =~ "Two-factor authentication is required"
    end

    test "maintainer is forbidden", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/workload-identities")

      assert conn.status == 403
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
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, workload_identity: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/workload-identities")

      assert conn.status == 404
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
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "added"

      assert [workload_identity] = WorkloadIdentities.list(package)
      assert workload_identity.repository == "acme/widget"
      assert workload_identity.repository_owner_id == "11"
      assert workload_identity.repository_id == "22"
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> post("/packages/#{package.name}/workload-identities", %{
          "workload_identity" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
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
            "repository" => "widget",
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
        repository: "acme/widget",
        workflow: "release.yml",
        environment: ""
      )

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
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert html_response(conn, 400) =~ "already configured for this package"
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
            "repository" => "widget",
            "workflow" => "release"
          }
        })

      body = html_response(conn, 400)
      assert body =~ "has invalid format"
      assert body =~ ~s(value="widget")
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
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "could not be resolved"
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
            "repository" => "private",
            "workflow" => "release.yml",
            "repository_id" => "22"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"

      assert [%{repository_owner_id: "11", repository_id: "22"}] =
               WorkloadIdentities.list(package)
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
            "repository" => "private",
            "workflow" => "release.yml"
          }
        })

      assert html_response(conn, 400) =~ "is required when Hex cannot resolve the repository"
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
            "repository" => "widget",
            "workflow" => "release.yml",
            "repository_id" => "99"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert [%{repository_id: "22"}] = WorkloadIdentities.list(package)
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
            "repository" => "widget",
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
            "repository" => "widget",
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
            "repository" => "widget",
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
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/workload-identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      assert WorkloadIdentities.list(package) == []
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
            "repository" => "widget",
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
        repository: "acme/covering",
        workflow: "release.yml"
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/excluded",
        workflow: "release.yml",
        packages: ["other"]
      )

      insert(:organization_workload_identity,
        organization: organization,
        repository: "acme/fetching"
      )

      body =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{repository.name}/#{package.name}/workload-identities")
        |> html_response(200)

      assert body =~ "published by the organization's workload identities"
      assert body =~ "acme/covering (release.yml)"
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

    test "keeps naming a member who is not an owner", %{
      organization: organization,
      repository: repository,
      package: package
    } do
      member = insert(:user)
      insert(:organization_user, organization: organization, user: member, role: "read")

      conn =
        build_conn()
        |> test_login(member)
        |> get("/packages/#{repository.name}/#{package.name}/workload-identities")

      assert conn.status == 403
    end
  end
end

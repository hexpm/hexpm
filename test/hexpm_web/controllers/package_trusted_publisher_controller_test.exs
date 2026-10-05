defmodule HexpmWeb.PackageTrustedPublisherControllerTest do
  use HexpmWeb.ConnCase, async: false

  import Mox

  alias Hexpm.TrustedPublishers

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

  describe "GET /packages/:name/trusted-publishers" do
    test "full owner with 2FA and sudo sees the page", %{
      full_owner: full_owner,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/trusted-publishers")

      assert html_response(conn, 200) =~ "Trusted publishers"
    end

    test "lists existing publishers", %{full_owner: full_owner, package: package} do
      insert(:trusted_publisher, package: package, repository: "acme/widget")

      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/trusted-publishers")

      assert html_response(conn, 200) =~ "acme/widget"
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> get("/packages/#{package.name}/trusted-publishers")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "refuses a full owner without two-factor authentication", %{package: package} do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")

      conn =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> get("/packages/#{package.name}/trusted-publishers")

      assert conn.status == 403
      assert conn.resp_body =~ "Two-factor authentication is required"
    end

    test "maintainer is forbidden", %{maintainer: maintainer, package: package} do
      conn =
        build_conn()
        |> test_login(maintainer)
        |> get("/packages/#{package.name}/trusted-publishers")

      assert conn.status == 403
    end

    test "non-owner is forbidden", %{non_owner: non_owner, package: package} do
      conn =
        build_conn()
        |> test_login(non_owner)
        |> get("/packages/#{package.name}/trusted-publishers")

      assert conn.status == 403
    end

    test "requires login", %{package: package} do
      conn = get(build_conn(), "/packages/#{package.name}/trusted-publishers")
      assert redirected_to(conn) =~ "/login"
    end

    test "returns 404 when the feature flag is disabled", %{
      full_owner: full_owner,
      package: package
    } do
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, trusted_publishers: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

      conn =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{package.name}/trusted-publishers")

      assert conn.status == 404
    end
  end

  describe "POST /packages/:name/trusted-publishers" do
    test "creates a publisher after resolving GitHub ids", %{
      full_owner: full_owner,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/trusted-publishers"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "added"

      assert [trusted_publisher] = TrustedPublishers.list(package)
      assert trusted_publisher.repository == "acme/widget"
      assert trusted_publisher.repository_owner_id == "11"
      assert trusted_publisher.repository_id == "22"
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert conn.status == 403
      assert TrustedPublishers.list(package) == []
    end

    test "rejects a duplicate publisher config with a 400 and shows the changeset error", %{
      full_owner: full_owner,
      package: package
    } do
      insert(:trusted_publisher,
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release"
          }
        })

      assert html_response(conn, 400) =~ "has invalid format"
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "missing",
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/trusted-publishers"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "could not be resolved"
      assert TrustedPublishers.list(package) == []
    end

    test "creates a publisher for a repository Hex cannot see when given its id", %{
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "private",
            "workflow" => "release.yml",
            "repository_id" => "22"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/trusted-publishers"
      assert [%{repository_owner_id: "11", repository_id: "22"}] = TrustedPublishers.list(package)
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "private",
            "workflow" => "release.yml"
          }
        })

      assert html_response(conn, 400) =~ "is required when Hex cannot resolve the repository"
      assert TrustedPublishers.list(package) == []
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml",
            "repository_id" => "99"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/trusted-publishers"
      assert [%{repository_id: "22"}] = TrustedPublishers.list(package)
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/trusted-publishers"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "try again later"
      assert TrustedPublishers.list(package) == []
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
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) == "/packages/#{package.name}/trusted-publishers"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "try again later"
      assert TrustedPublishers.list(package) == []
    end

    test "is forbidden for maintainer even with sudo", %{
      maintainer: maintainer,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(maintainer, sudo: true)
        |> post("/packages/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert conn.status == 403
    end
  end

  describe "DELETE /packages/:name/trusted-publishers/:id" do
    test "full owner with sudo removes a publisher", %{
      full_owner: full_owner,
      package: package
    } do
      trusted_publisher = insert(:trusted_publisher, package: package)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/trusted-publishers/#{trusted_publisher.id}")

      assert redirected_to(conn) == "/packages/#{package.name}/trusted-publishers"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "removed"
      assert TrustedPublishers.get(package, trusted_publisher.id) == nil
    end

    test "returns 404 for unknown id", %{full_owner: full_owner, package: package} do
      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/trusted-publishers/999999")

      assert conn.status == 404
    end

    test "returns 404 for cross-package id", %{full_owner: full_owner, package: package} do
      other =
        insert(:package, package_owners: [build(:package_owner, user: full_owner, level: "full")])

      trusted_publisher = insert(:trusted_publisher, package: other)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: true)
        |> delete("/packages/#{package.name}/trusted-publishers/#{trusted_publisher.id}")

      assert conn.status == 404
    end

    test "redirects to /sudo when no sudo mode", %{full_owner: full_owner, package: package} do
      trusted_publisher = insert(:trusted_publisher, package: package)

      conn =
        build_conn()
        |> test_login(full_owner, sudo: false)
        |> delete("/packages/#{package.name}/trusted-publishers/#{trusted_publisher.id}")

      assert redirected_to(conn) =~ "/sudo"
    end

    test "refuses a full owner without two-factor authentication", %{package: package} do
      full_owner_no_tfa = insert(:user)
      insert(:package_owner, package: package, user: full_owner_no_tfa, level: "full")
      trusted_publisher = insert(:trusted_publisher, package: package)

      conn =
        build_conn()
        |> test_login(full_owner_no_tfa)
        |> delete("/packages/#{package.name}/trusted-publishers/#{trusted_publisher.id}")

      assert conn.status == 403
      assert TrustedPublishers.get(package, trusted_publisher.id)
    end

    test "is forbidden for maintainer even with sudo", %{
      maintainer: maintainer,
      package: package
    } do
      trusted_publisher = insert(:trusted_publisher, package: package)

      conn =
        build_conn()
        |> test_login(maintainer, sudo: true)
        |> delete("/packages/#{package.name}/trusted-publishers/#{trusted_publisher.id}")

      assert conn.status == 403
    end
  end

  describe "organization billing" do
    setup do
      org_user = insert(:user_with_tfa)
      organization = insert(:organization, user: org_user, billing_active: false)
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

    test "refuses create for a private repository package with no active billing", %{
      org_user: org_user,
      repository: repository,
      package: package
    } do
      conn =
        build_conn()
        |> test_login(org_user, sudo: true)
        |> post("/packages/#{repository.name}/#{package.name}/trusted-publishers", %{
          "trusted_publisher" => %{
            "provider" => "github",
            "repository_owner" => "acme",
            "repository" => "widget",
            "workflow" => "release.yml"
          }
        })

      assert redirected_to(conn) ==
               "/packages/#{repository.name}/#{package.name}/trusted-publishers"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no active billing subscription"
      assert TrustedPublishers.list(package) == []
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
        |> get("/packages/#{repository.name}/#{package.name}/trusted-publishers")

      assert html_response(conn, 200) =~ "Trusted publishers"
    end

    test "lists the organization publishers that can publish the package", %{
      organization: organization,
      repository: repository,
      full_owner: full_owner,
      package: package
    } do
      insert(:organization_trusted_publisher,
        organization: organization,
        role: "write",
        repository: "acme/covering",
        workflow: "release.yml"
      )

      insert(:organization_trusted_publisher,
        organization: organization,
        role: "write",
        repository: "acme/excluded",
        workflow: "release.yml",
        packages: ["other"]
      )

      insert(:organization_trusted_publisher,
        organization: organization,
        repository: "acme/fetching"
      )

      body =
        build_conn()
        |> test_login(full_owner)
        |> get("/packages/#{repository.name}/#{package.name}/trusted-publishers")
        |> html_response(200)

      assert body =~ "Organization trusted publishers"
      assert body =~ "acme/covering (release.yml)"
      assert body =~ "/dashboard/orgs/#{repository.name}/trusted-publishers"
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
        |> get("/packages/#{repository.name}/#{package.name}/trusted-publishers")

      missing =
        build_conn()
        |> test_login(outsider)
        |> get("/packages/#{repository.name}/no-such-package/trusted-publishers")

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
        |> get("/packages/#{repository.name}/#{package.name}/trusted-publishers")

      assert conn.status == 403
    end
  end
end

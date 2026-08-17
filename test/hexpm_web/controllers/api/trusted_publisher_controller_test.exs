defmodule HexpmWeb.API.TrustedPublisherControllerTest do
  use HexpmWeb.ConnCase, async: false
  import Mox

  setup :verify_on_exit!

  setup do
    user = insert(:user)

    package =
      insert(:package,
        package_owners: [build(:package_owner, user: user, level: "full")]
      )

    %{user: user, package: package}
  end

  describe "GET /api/packages/:name/trusted_publishers" do
    test "lists publishers for package owners", %{user: user, package: package} do
      insert(:trusted_publisher, package: package, repository: "acme/widget")

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("/api/packages/#{package.name}/trusted_publishers")

      [publisher] = json_response(conn, 200)
      assert publisher["provider"] == "github"
      assert publisher["github_repository"] == "acme/widget"
    end

    test "requires authentication", %{package: package} do
      build_conn()
      |> get("/api/packages/#{package.name}/trusted_publishers")
      |> json_response(401)
    end
  end

  describe "GET /api/packages/:name/trusted_publishers/:id" do
    test "shows a publisher", %{user: user, package: package} do
      publisher = insert(:trusted_publisher, package: package, repository: "acme/widget")

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("/api/packages/#{package.name}/trusted_publishers/#{publisher.id}")

      body = json_response(conn, 200)
      assert body["id"] == publisher.id
      assert body["github_repository"] == "acme/widget"
    end

    test "returns 404 for unknown id", %{user: user, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("/api/packages/#{package.name}/trusted_publishers/999999")
      |> json_response(404)
    end

    test "returns 404 for cross-package id", %{user: user, package: package} do
      other =
        insert(:package, package_owners: [build(:package_owner, user: user, level: "full")])

      publisher = insert(:trusted_publisher, package: other)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("/api/packages/#{package.name}/trusted_publishers/#{publisher.id}")
      |> json_response(404)
    end
  end

  describe "POST /api/packages/:name/trusted_publishers" do
    test "creates a publisher after resolving GitHub ids", %{user: user, package: package} do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "github_repository" => "widget",
          "workflow" => "release.yml"
        })

      body = json_response(conn, 201)
      assert body["github_repository"] == "acme/widget"
      assert body["workflow"] == "release.yml"
      assert body["environment"] == nil
    end

    test "rewrites body repository param without shadowing Hex repository", %{
      user: user,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "repository" => "widget",
          "workflow" => "release.yml"
        })

      body = json_response(conn, 201)
      assert body["github_repository"] == "acme/widget"
    end

    test "rejects duplicate publisher config", %{user: user, package: package} do
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
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "github_repository" => "widget",
          "workflow" => "release.yml"
        })

      assert json_response(conn, 422)["errors"]["repository"]
    end

    test "returns validation error when GitHub repository resolution fails", %{
      user: user,
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
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "missing",
          "github_repository" => "widget",
          "workflow" => "release.yml"
        })

      assert json_response(conn, 422)["errors"]["github_repository"]
      assert Hexpm.TrustedPublishers.list(package) == []
    end

    test "creates a publisher for a repository Hex cannot see when given its id", %{
      user: user,
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
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "github_repository" => "private",
          "workflow" => "release.yml",
          "repository_id" => 22
        })

      assert json_response(conn, 201)["github_repository"] == "acme/private"

      assert [%{repository_owner_id: "11", repository_id: "22"}] =
               Hexpm.TrustedPublishers.list(package)
    end

    test "refuses a repository Hex cannot see without its id", %{user: user, package: package} do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/private", _, _ ->
        {:ok, 404, [], %{}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 11}}
      end)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "github_repository" => "private",
          "workflow" => "release.yml"
        })

      assert json_response(conn, 422)["errors"]["repository_id"]
      assert Hexpm.TrustedPublishers.list(package) == []
    end

    test "prefers the resolved repository id over a supplied one", %{
      user: user,
      package: package
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 22, "owner" => %{"id" => 11}}}
      end)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "github_repository" => "widget",
          "workflow" => "release.yml",
          "repository_id" => 99
        })

      assert json_response(conn, 201)
      assert [%{repository_id: "22"}] = Hexpm.TrustedPublishers.list(package)
    end

    test "returns 503 when GitHub is unavailable", %{user: user, package: package} do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 500, [], %{}}
      end)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "github_repository" => "widget",
          "workflow" => "release.yml"
        })

      assert json_response(conn, 503)["message"] =~ "try again later"
      assert Hexpm.TrustedPublishers.list(package) == []
    end

    test "returns 503 when GitHub cannot be reached", %{user: user, package: package} do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:error, :timeout}
      end)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> post("/api/packages/#{package.name}/trusted_publishers", %{
          "provider" => "github",
          "repository_owner" => "acme",
          "github_repository" => "widget",
          "workflow" => "release.yml"
        })

      assert json_response(conn, 503)
      assert Hexpm.TrustedPublishers.list(package) == []
    end

    test "rejects maintainer-level owners", %{package: package} do
      maintainer = insert(:user)
      insert(:package_owner, package: package, user: maintainer, level: "maintainer")

      build_conn()
      |> put_req_header("authorization", key_for(maintainer))
      |> post("/api/packages/#{package.name}/trusted_publishers", %{
        "provider" => "github",
        "repository_owner" => "acme",
        "github_repository" => "widget",
        "workflow" => "release.yml"
      })
      |> json_response(403)
    end

    test "rejects package-scoped keys", %{user: user, package: package} do
      key =
        key_for(user, [
          %{domain: "package", resource: "hexpm/#{package.name}"}
        ])

      build_conn()
      |> put_req_header("authorization", key)
      |> post("/api/packages/#{package.name}/trusted_publishers", %{
        "provider" => "github",
        "repository_owner" => "acme",
        "github_repository" => "widget",
        "workflow" => "release.yml"
      })
      |> json_response(401)
    end

    test "returns 404 when feature flag is disabled", %{user: user, package: package} do
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, trusted_publishers: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("/api/packages/#{package.name}/trusted_publishers")
      |> json_response(404)
    end
  end

  describe "DELETE /api/packages/:name/trusted_publishers/:id" do
    test "deletes a publisher", %{user: user, package: package} do
      publisher = insert(:trusted_publisher, package: package)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("/api/packages/#{package.name}/trusted_publishers/#{publisher.id}")
      |> response(204)

      assert Hexpm.TrustedPublishers.get(package, publisher.id) == nil
    end
  end
end

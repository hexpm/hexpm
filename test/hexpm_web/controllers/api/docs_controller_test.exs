defmodule HexpmWeb.API.DocsControllerTest do
  use HexpmWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Repository.{Package, Repository}

  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  describe "GET /api/packages/:name/releases/:version/docs" do
    test "return 404 on no docs" do
      package = insert(:package)
      insert(:release, package: package, version: "0.0.1", has_docs: false)

      build_conn()
      |> get("api/packages/#{package.name}/releases/0.0.1/docs")
      |> response(404)
    end

    test "redirects to tarball" do
      package = insert(:package)
      insert(:release, package: package, version: "0.0.1", has_docs: true)

      conn = get(build_conn(), "api/packages/#{package.name}/releases/0.0.1/docs")
      assert redirected_to(conn) =~ "/docs/#{package.name}-0.0.1.tar.gz"
    end
  end

  describe "GET /api/repos/:repo/packages/:name/releases/:version/docs" do
    test "authorizes", %{user: user} do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id)
      insert(:release, package: package, version: "0.0.1", has_docs: true)

      build_conn()
      |> get("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1/docs")
      |> response(403)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1/docs")
      |> response(403)
    end

    test "redirects to tarball", %{user: user} do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id)
      insert(:release, package: package, version: "0.0.1", has_docs: true)
      insert(:organization_user, organization: repository.organization, user: user)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{repository.name}/packages/#{package.name}/releases/0.0.1/docs")

      assert redirected_to(conn) =~ "/repos/#{repository.name}/docs/#{package.name}-0.0.1.tar.gz"
    end
  end

  describe "POST /api/packages/:name/releases/:version/docs" do
    test "release docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      assert Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs
      assert Hexpm.Store.get(nil, :s3_bucket, "docs/#{package.name}-0.0.1.tar.gz", [])

      log = Hexpm.Repo.one!(AuditLog)
      assert log.user_id == user.id
      assert log.action == "docs.publish"
      assert log.params["package"]["name"] == package.name
      assert log.params["release"]["version"] == "0.0.1"
    end
  end

  describe "POST /api/repos/:repository/packages/:name/releases/:version/docs" do
    test "release docs authorizes user", %{user: user} do
      repository = insert(:repository)

      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")

      publish_docs(user, repository, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(403)

      refute Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs
    end

    test "release docs authorizes organization" do
      repository = insert(:repository)
      organization = repository.organization
      other_organization = insert(:organization)

      package =
        insert(
          :package,
          repository_id: repository.id
        )

      insert(:release, package: package, version: "0.0.1")

      publish_docs(
        other_organization,
        repository,
        package,
        "0.0.1",
        [{'index.html', "package v0.0.1"}]
      )
      |> response(403)

      refute Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs

      publish_docs(organization, repository, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      assert Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs
    end

    test "release docs", %{user: user} do
      repository = insert(:repository)

      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")
      insert(:organization_user, organization: repository.organization, user: user)

      publish_docs(user, repository, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      assert Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs

      tar_key = "repos/#{repository.name}/docs/#{package.name}-0.0.1.tar.gz"
      assert Hexpm.Store.get(nil, :s3_bucket, tar_key, [])
    end
  end

  describe "DELETE /api/packages/:name/releases/:version/docs" do
    test "delete release with docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      assert Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs

      revert_release(user, package, "0.0.1")
      |> response(204)

      # Check release was deleted
      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1")
      refute Hexpm.Store.get(nil, :s3_bucket, "docs/#{package.name}-0.0.1.tar.gz", [])

      # Check docs were deleted
      assert get(build_conn(), "api/packages/#{package.name}/releases/0.0.1/docs").status in 400..499
    end

    test "delete docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      # Revert docs
      revert_docs(user, package, "0.0.1")
      |> response(204)

      # Check docs were deleted
      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1").has_docs
      refute Hexpm.Store.get(nil, :s3_bucket, "docs/#{package.name}-0.0.1.tar.gz", [])

      [%{action: "docs.publish"}, log] = Hexpm.Repo.all(from(al in AuditLog, order_by: al.id))

      assert log.user_id == user.id
      assert log.action == "docs.revert"
      assert log.params["package"]["name"] == package.name
      assert log.params["release"]["version"] == "0.0.1"
    end
  end

  describe "DELETE /api/repos/:repository/packages/:name/releases/:version/docs" do
    test "delete docs authorizes", %{user: user1} do
      user2 = insert(:user)
      repository = insert(:repository)

      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [
            build(:package_owner, user: user1),
            build(:package_owner, user: user2)
          ]
        )

      insert(:release, package: package, version: "0.0.1")
      insert(:organization_user, organization: repository.organization, user: user1)

      publish_docs(user1, repository, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      revert_docs(user2, repository, package, "0.0.1")
      |> response(403)

      assert Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1").has_docs

      tar_key = "repos/#{repository.name}/docs/#{package.name}-0.0.1.tar.gz"
      assert Hexpm.Store.get(nil, :s3_bucket, tar_key, [])
    end

    test "delete docs", %{user: user} do
      repository = insert(:repository)

      package =
        insert(
          :package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")
      insert(:organization_user, organization: repository.organization, user: user)

      publish_docs(user, repository, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      revert_docs(user, repository, package, "0.0.1")
      |> response(204)

      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1").has_docs

      tar_key = "repos/#{repository.name}/docs/#{package.name}-0.0.1.tar.gz"
      refute Hexpm.Store.get(nil, :s3_bucket, tar_key, [])
    end
  end

  defp publish_docs(user, %Package{name: name}, version, files) do
    body = create_tarball(files)

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(user))
    |> post("api/packages/#{name}/releases/#{version}/docs", body)
  end

  def revert_docs(user, %Package{name: package}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/packages/#{package}/releases/#{version}/docs")
  end

  defp publish_docs(user, %Repository{name: repository}, %Package{name: package}, version, files) do
    body = create_tarball(files)

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(user))
    |> post("api/repos/#{repository}/packages/#{package}/releases/#{version}/docs", body)
  end

  def revert_docs(user, %Repository{name: repository}, %Package{name: package}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/repos/#{repository}/packages/#{package}/releases/#{version}/docs")
  end

  def revert_release(user, %Package{name: package}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/packages/#{package}/releases/#{version}")
  end

  defp create_tarball(files) do
    path = Path.join(Application.get_env(:hexpm, :tmp_dir), "release-docs.tar.gz")
    :ok = :erl_tar.create(String.to_charlist(path), files, [:compressed])
    File.read!(path)
  end
end

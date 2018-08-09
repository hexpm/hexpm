defmodule Hexpm.Web.API.DocsControllerTest do
  use Hexpm.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  alias Hexpm.Accounts.{AuditLog, Organization}
  alias Hexpm.Repository.Package

  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  defp path(path) do
    response = build_conn() |> get(path)

    if response.status == 200 do
      response.resp_body
    end
  end

  describe "POST /api/packages/:name/releases/:version/docs" do
    test "release docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      assert Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs

      log = Hexpm.Repo.one!(AuditLog)
      assert log.user_id == user.id
      assert log.action == "docs.publish"
      assert log.params["package"]["name"] == package.name
      assert log.params["release"]["version"] == "0.0.1"

      assert path("docs/#{package.name}/index.html") == "package v0.0.1"
      assert path("docs/#{package.name}/0.0.1/index.html") == "package v0.0.1"

      docs_url = Hexpm.Utils.docs_html_url(Organization.hexpm(), package, nil)
      assert path("docs/sitemap.xml") =~ docs_url
    end

    test "update main docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")
      insert(:release, package: package, version: "0.5.0")

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      publish_docs(user, package, "0.5.0", [{'index.html', "package v0.5.0"}])
      |> response(201)

      assert path("docs/#{package.name}/index.html") == "package v0.5.0"
      assert path("docs/#{package.name}/0.0.1/index.html") == "package v0.0.1"
    end

    test "dont update main docs for older versions", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")
      insert(:release, package: package, version: "0.5.0")

      publish_docs(user, package, "0.5.0", [
        {'index.html', "package v0.5.0"},
        {'remove.html', "dont remove me"}
      ])
      |> response(201)

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      assert path("docs/#{package.name}/index.html") == "package v0.5.0"
      assert path("docs/#{package.name}/remove.html") == "dont remove me"
    end

    test "overwrite docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")
      insert(:release, package: package, version: "0.5.0")

      publish_docs(user, package, "0.0.1", [
        {'index.html', "package v0.0.1"},
        {'remove.html', "please remove me"}
      ])
      |> response(201)

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1 (updated)"}])
      |> response(201)

      assert path("docs/#{package.name}/index.html") == "package v0.0.1 (updated)"
      assert path("docs/#{package.name}/0.0.1/index.html") == "package v0.0.1 (updated)"
      refute path("docs/#{package.name}/remove.html")
      refute path("docs/#{package.name}/0.0.1/remove.html")
    end

    test "beta docs do not overwrite stable main docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.5.0")
      insert(:release, package: package, version: "1.0.0-beta")

      publish_docs(user, package, "0.5.0", [
        {'index.html', "package v0.5.0"},
        {'remove.html', "dont remove me"}
      ])
      |> response(201)

      publish_docs(user, package, "1.0.0-beta", [{'index.html', "package v1.0.0-beta"}])
      |> response(201)

      assert path("docs/#{package.name}/index.html") == "package v0.5.0"
      assert path("docs/#{package.name}/remove.html") == "dont remove me"
      assert path("docs/#{package.name}/1.0.0-beta/index.html") == "package v1.0.0-beta"
    end

    test "update main docs even with beta docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")
      insert(:release, package: package, version: "1.0.0-beta")
      insert(:release, package: package, version: "0.5.0")

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      publish_docs(user, package, "1.0.0-beta", [{'index.html', "package v1.0.0-beta"}])
      |> response(201)

      publish_docs(user, package, "0.5.0", [{'index.html', "package v0.5.0"}])
      |> response(201)

      assert path("docs/#{package.name}/index.html") == "package v0.5.0"
      assert path("docs/#{package.name}/0.0.1/index.html") == "package v0.0.1"
      assert path("docs/#{package.name}/1.0.0-beta/index.html") == "package v1.0.0-beta"
      assert path("docs/#{package.name}/0.5.0/index.html") == "package v0.5.0"
    end

    test "beta docs can overwrite beta main docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1-beta")
      insert(:release, package: package, version: "1.0.0-beta")

      publish_docs(user, package, "0.0.1-beta", [{'index.html', "package v0.0.1-beta"}])
      |> response(201)

      publish_docs(user, package, "1.0.0-beta", [{'index.html', "package v1.0.0-beta"}])
      |> response(201)

      assert path("docs/#{package.name}/index.html") == "package v1.0.0-beta"
      assert path("docs/#{package.name}/1.0.0-beta/index.html") == "package v1.0.0-beta"
    end

    test "dont allow version directories in docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")

      result =
        publish_docs(user, package, "0.0.1", [{'1.2.3', "package   v0.0.1"}])
        |> json_response(422)

      assert result["errors"]["tar"] == "directory name not allowed to match a semver version"
    end
  end

  describe "POST /api/repos/:repository/packages/:name/releases/:version/docs" do
    test "release docs authorizes", %{user: user} do
      organization = insert(:organization)

      package =
        insert(
          :package,
          organization_id: organization.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")

      publish_docs(user, organization, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(403)

      refute Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs
    end

    test "release docs", %{user: user} do
      organization = insert(:organization)

      package =
        insert(
          :package,
          organization_id: organization.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")
      insert(:organization_user, organization: organization, user: user)

      publish_docs(user, organization, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      assert Hexpm.Repo.get_by!(assoc(package, :releases), version: "0.0.1").has_docs
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

      # Check docs were deleted
      assert get(build_conn(), "api/packages/#{package.name}/releases/0.0.1/docs").status in 400..499
      assert get(build_conn(), "docs/#{package.name}/0.0.1/index.html").status in 400..499
    end

    test "delete docs", %{user: user} do
      package = insert(:package, package_owners: [build(:package_owner, user: user)])
      insert(:release, package: package, version: "0.0.1")
      insert(:release, package: package, version: "0.5.0")
      insert(:release, package: package, version: "2.0.0")

      publish_docs(user, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      publish_docs(user, package, "0.5.0", [{'index.html', "package v0.5.0"}])
      |> response(201)

      publish_docs(user, package, "2.0.0", [{'index.html', "package v2.0.0"}])
      |> response(201)

      # Revert middle release
      revert_docs(user, package, "0.5.0")
      |> response(204)

      # Check release was deleted
      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.5.0").has_docs

      [%{action: "docs.publish"}, %{action: "docs.publish"}, %{action: "docs.publish"}, log] =
        Hexpm.Repo.all(from(al in AuditLog, order_by: al.id))

      assert log.user_id == user.id
      assert log.action == "docs.revert"
      assert log.params["package"]["name"] == package.name
      assert log.params["release"]["version"] == "0.5.0"

      # Check docs were deleted
      assert get(build_conn(), "api/packages/#{package.name}/releases/0.5.0/docs").status in 400..499
      assert get(build_conn(), "docs/#{package.name}/0.5.0/index.html").status in 400..499

      assert path("docs/#{package.name}/index.html") == "package v2.0.0"

      # Revert latest release
      revert_docs(user, package, "2.0.0")
      |> response(204)

      # Check release was deleted
      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "2.0.0").has_docs

      # Check docs were deleted
      assert get(build_conn(), "api/packages/#{package.name}/releases/2.0.0/docs").status in 400..499
      assert get(build_conn(), "docs/#{package.name}/2.0.0/index.html").status in 400..499

      # TODO: update top-level docs to the next-to-last version
      assert path("docs/#{package.name}/index.html") == "package v2.0.0"

      # Revert remaining release
      revert_docs(user, package, "0.0.1")
      |> response(204)

      # Check release was deleted
      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1").has_docs

      # Check docs were deleted
      assert get(build_conn(), "api/packages/#{package.name}/releases/0.0.1/docs").status in 400..499
      assert get(build_conn(), "docs/#{package.name}/0.0.1/index.html").status in 400..499

      # TODO: deleting last version should remove top-level docs
      assert path("docs/#{package.name}/index.html") == "package v2.0.0"
    end
  end

  describe "DELETE /api/repos/:repository/packages/:name/releases/:version/docs" do
    test "delete docs authorizes", %{user: user1} do
      user2 = insert(:user)
      organization = insert(:organization)

      package =
        insert(
          :package,
          organization_id: organization.id,
          package_owners: [
            build(:package_owner, user: user1),
            build(:package_owner, user: user2)
          ]
        )

      insert(:release, package: package, version: "0.0.1")
      insert(:organization_user, organization: organization, user: user1)

      publish_docs(user1, organization, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      revert_docs(user2, organization, package, "0.0.1")
      |> response(403)

      assert Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1").has_docs
    end

    test "delete docs", %{user: user} do
      organization = insert(:organization)

      package =
        insert(
          :package,
          organization_id: organization.id,
          package_owners: [build(:package_owner, user: user)]
        )

      insert(:release, package: package, version: "0.0.1")
      insert(:organization_user, organization: organization, user: user)

      publish_docs(user, organization, package, "0.0.1", [{'index.html', "package v0.0.1"}])
      |> response(201)

      revert_docs(user, organization, package, "0.0.1")
      |> response(204)

      refute Hexpm.Repo.get_by(assoc(package, :releases), version: "0.0.1").has_docs
    end
  end

  defp publish_docs(user, %Package{name: name}, version, files) do
    body = create_tarball(files)

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(user))
    |> post("api/packages/#{name}/releases/#{version}/docs", body)
  end

  def revert_docs(user, %Package{name: name}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/packages/#{name}/releases/#{version}/docs")
  end

  defp publish_docs(user, %Organization{name: organization}, %Package{name: name}, version, files) do
    body = create_tarball(files)

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(user))
    |> post("api/repos/#{organization}/packages/#{name}/releases/#{version}/docs", body)
  end

  def revert_docs(user, %Organization{name: organization}, %Package{name: name}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/repos/#{organization}/packages/#{name}/releases/#{version}/docs")
  end

  def revert_release(user, %Package{name: name}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/packages/#{name}/releases/#{version}")
  end

  defp create_tarball(files) do
    path = Path.join(Application.get_env(:hexpm, :tmp_dir), "release-docs.tar.gz")
    :ok = :erl_tar.create(String.to_charlist(path), files, [:compressed])
    File.read!(path)
  end
end

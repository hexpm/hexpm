defmodule HexpmWeb.API.RetirementControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user = insert(:user)
    repository = insert(:repository)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])

    repository_package =
      insert(
        :package,
        repository_id: repository.id,
        package_owners: [build(:package_owner, user: user)]
      )

    insert(:release, package: package, version: "1.0.0")

    insert(
      :release,
      package: package,
      version: "2.0.0",
      retirement: %Hexpm.Repository.ReleaseRetirement{reason: "security"}
    )

    insert(:release, package: repository_package, version: "1.0.0")

    insert(
      :release,
      package: repository_package,
      version: "2.0.0",
      retirement: %Hexpm.Repository.ReleaseRetirement{reason: "security"}
    )

    %{
      user: user,
      package: package,
      repository: repository,
      repository_package: repository_package
    }
  end

  describe "POST /api/packages/:name/releases/:version/retire" do
    test "retire release", %{user: user, package: package} do
      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post("api/packages/#{package.name}/releases/1.0.0/retire", params)
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      assert release.retirement
      assert release.retirement.reason == "security"
      assert release.retirement.message == "See CVE-NNNN"
    end
  end

  describe "POST /api/repos/:repository/packages/:name/releases/:version/retire" do
    test "returns 404 if you are not authorized", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> post(
        "api/repos/#{repository.name}/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{repository.name}/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "returns 404 for unknown repository", %{user: user, repository_package: package} do
      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> post(
        "api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "returns 404 for missing package if you are not authorized", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> post(
        "api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE/releases/1.0.0/retire",
        params
      )
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE/releases/1.0.0/retire",
        params
      )
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "returns 404 for missing package if you are authorized", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      insert(:organization_user, organization: repository.organization, user: user, role: "write")

      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE/releases/1.0.0/retire",
        params
      )
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "retire release", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      insert(:organization_user, organization: repository.organization, user: user)

      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{repository.name}/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      assert release.retirement
      assert release.retirement.reason == "security"
      assert release.retirement.message == "See CVE-NNNN"
    end

    test "retire release using write permission and without package owner", %{
      repository: repository,
      repository_package: package
    } do
      user = insert(:user)
      insert(:organization_user, organization: repository.organization, user: user, role: "write")

      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{repository.name}/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      assert release.retirement
      assert release.retirement.reason == "security"
      assert release.retirement.message == "See CVE-NNNN"
    end
  end

  describe "DELETE /api/packages/:name/releases/:version/retire" do
    test "unretire release", %{user: user, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/packages/#{package.name}/releases/2.0.0/retire")
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      refute release.retirement
    end
  end

  describe "DELETE /api/repos/:repository/packages/:name/releases/:version/retire" do
    test "returns 404 if you are not authorized", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      build_conn()
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/2.0.0/retire")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/2.0.0/retire")
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "returns 404 for unknown repository", %{user: user, repository_package: package} do
      build_conn()
      |> delete("api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/releases/2.0.0/retire")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/releases/2.0.0/retire")
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "returns 404 for missing package if you are not authorized", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      build_conn()
      |> delete("api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE/releases/2.0.0/retire")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE/releases/2.0.0/retire")
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "returns 404 for missing package if you are authorized", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      insert(:organization_user, organization: repository.organization, user: user, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/UNKNOWN_PACKAGE/releases/2.0.0/retire")
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "unretire release", %{
      user: user,
      repository: repository,
      repository_package: package
    } do
      insert(:organization_user, organization: repository.organization, user: user)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/2.0.0/retire")
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      refute release.retirement
    end

    test "unretire release using write permission and without package owner", %{
      repository: repository,
      repository_package: package
    } do
      user = insert(:user)
      insert(:organization_user, organization: repository.organization, user: user, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{repository.name}/packages/#{package.name}/releases/2.0.0/retire")
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      refute release.retirement
    end
  end
end

defmodule HexpmWeb.API.RetirementControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user = insert(:user)
    organization = insert(:organization)
    package = insert(:package, package_owners: [build(:package_owner, user: user)])

    organization_package =
      insert(
        :package,
        organization_id: organization.id,
        package_owners: [build(:package_owner, user: user)]
      )

    insert(:release, package: package, version: "1.0.0")

    insert(
      :release,
      package: package,
      version: "2.0.0",
      retirement: %Hexpm.Repository.ReleaseRetirement{reason: "security"}
    )

    insert(:release, package: organization_package, version: "1.0.0")

    insert(
      :release,
      package: organization_package,
      version: "2.0.0",
      retirement: %Hexpm.Repository.ReleaseRetirement{reason: "security"}
    )

    %{
      user: user,
      package: package,
      organization: organization,
      organization_package: organization_package
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
    test "returns 403 if you are not authorized", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{organization.name}/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(403)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "returns 403 for unknown repository", %{user: user, organization_package: package} do
      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(403)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "returns 403 for missing package if you are not authorized", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/releases/1.0.0/retire",
        params
      )
      |> response(403)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "returns 404 for missing package if you are authorized", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user, role: "write")

      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/releases/1.0.0/retire",
        params
      )
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      refute release.retirement
    end

    test "retire release", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user)

      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{organization.name}/packages/#{package.name}/releases/1.0.0/retire",
        params
      )
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "1.0.0")
      assert release.retirement
      assert release.retirement.reason == "security"
      assert release.retirement.message == "See CVE-NNNN"
    end

    test "retire release using write permission and without package owner", %{
      organization: organization,
      organization_package: package
    } do
      user = insert(:user)
      insert(:organization_user, organization: organization, user: user, role: "write")

      params = %{"reason" => "security", "message" => "See CVE-NNNN"}

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> post(
        "api/repos/#{organization.name}/packages/#{package.name}/releases/1.0.0/retire",
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
    test "returns 403 if you are not authorized", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{organization.name}/packages/#{package.name}/releases/2.0.0/retire")
      |> response(403)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "returns 403 for unknown repository", %{user: user, organization_package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/releases/2.0.0/retire")
      |> response(403)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "returns 403 for missing package if you are not authorized", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/releases/2.0.0/retire")
      |> response(403)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "returns 404 for missing package if you are authorized", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/releases/2.0.0/retire")
      |> response(404)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      assert release.retirement
    end

    test "unretire release", %{
      user: user,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user)

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{organization.name}/packages/#{package.name}/releases/2.0.0/retire")
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      refute release.retirement
    end

    test "unretire release using write permission and without package owner", %{
      organization: organization,
      organization_package: package
    } do
      user = insert(:user)
      insert(:organization_user, organization: organization, user: user, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> delete("api/repos/#{organization.name}/packages/#{package.name}/releases/2.0.0/retire")
      |> response(204)

      release = Hexpm.Repository.Releases.get(package, "2.0.0")
      refute release.retirement
    end
  end
end

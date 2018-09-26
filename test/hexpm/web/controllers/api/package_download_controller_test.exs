defmodule Hexpm.Web.API.PackageDownloadControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    user = insert(:user)
    unauthorized_user = insert(:user)
    organization = insert(:organization)

    package1 =
      insert(
        :package,
        name: "Hexpm.Web.API.PackageControllerTest",
        inserted_at: ~N[2030-01-01 00:00:00]
      )

    package2 = insert(:package, updated_at: ~N[2030-01-01 00:00:00])

    package3 =
      insert(:package, organization_id: organization.id, updated_at: ~N[2030-01-01 00:00:00])

    package4 = insert(:package)
    insert(:release, package: package1, version: "0.0.1", has_docs: true)
    insert(:release, package: package3, version: "0.0.1")

    insert(
      :release,
      package: package4,
      version: "0.0.1",
      retirement: %{reason: "other", message: "not backward compatible"}
    )

    insert(:release, package: package4, version: "1.0.0")
    insert(:organization_user, organization: organization, user: user)

    %{
      package1: package1,
      package2: package2,
      package3: package3,
      package4: package4,
      organization: organization,
      user: user,
      unauthorized_user: unauthorized_user
    }
  end

  describe "GET /api/packages/:name/downloads" do
    test "get package downloads with no downloads", %{package1: package1} do
      conn = get(build_conn(), "api/packages/#{package1.name}/downloads")
      result = json_response(conn, 200)
      assert result["name"] == package1.name
      assert result["inserted_at"] == "2030-01-01T00:00:00.000000Z"
      assert String.slice(result["updated_at"], -1, 1) == "Z"
      assert result["url"] =~ "/api/packages/#{package1.name}"
      assert result["html_url"] =~ "/packages/#{package1.name}"
      assert result["docs_html_url"] =~ "/#{package1.name}"
      assert result["downloads"] == []
    end

    test "get package downloads with some downloads", %{package2: package2} do
      days_ago_10 = Hexpm.Utils.utc_days_ago(10)
      days_ago_11 = Hexpm.Utils.utc_days_ago(11)
      days_ago_92 = Hexpm.Utils.utc_days_ago(92)

      insert(
        :release,
        package_id: package2.id,
        daily_downloads: [
          build(:download, downloads: 12, day: days_ago_10),
          build(:download, downloads: 317, day: days_ago_11),
          build(:download, downloads: 0, day: days_ago_92)
        ]
      )

      conn = get(build_conn(), "api/packages/#{package2.name}/downloads")
      result = json_response(conn, 200)

      assert result["downloads"] == [
               ["#{days_ago_92}", 0],
               ["#{days_ago_11}", 317],
               ["#{days_ago_10}", 12]
             ]
    end

    test "get package downloads for non namespaced private organization", %{
      user: user,
      package3: package3
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/packages/#{package3.name}/downloads")
      |> json_response(404)
    end

    test "get package downloads for unauthenticated private organization", %{
      organization: organization,
      package3: package3
    } do
      build_conn()
      |> get("api/repos/#{organization.name}/packages/#{package3.name}/downloads")
      |> json_response(403)
    end

    test "get package downloads returns 403 for unknown organization", %{package1: package1} do
      build_conn()
      |> get("api/repos/UNKNOWN_REPOSITORY/packages/#{package1.name}/downloads")
      |> json_response(403)
    end

    test "get package downloads returns 403 for unknown package if you are not authorized", %{
      organization: organization
    } do
      build_conn()
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/downloads")
      |> json_response(403)
    end

    test "get package downloads returns 404 for unknown package if you are authorized", %{
      user: user,
      organization: organization
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/downloads")
      |> json_response(404)
    end

    test "get package downloads for authenticated private organization", %{
      user: user,
      organization: organization,
      package3: package3
    } do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{organization.name}/packages/#{package3.name}/downloads")
        |> json_response(200)

      assert result["name"] == package3.name
      assert result["repository"] == organization.name
      assert result["url"] =~ "/api/repos/#{organization.name}/packages/#{package3.name}"
      assert result["html_url"] =~ "/packages/#{organization.name}/#{package3.name}"
      assert result["downloads"] == []
    end
  end
end

defmodule HexpmWeb.API.PackageControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    user = insert(:user)
    unauthorized_user = insert(:user)
    organization = insert(:organization)

    package1 =
      insert(
        :package,
        name: "HexpmWeb.API.PackageControllerTest",
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

  describe "GET /api/packages" do
    test "multiple packages", %{package1: package1} do
      conn = get(build_conn(), "api/packages")
      result = json_response(conn, 200)
      assert length(result) == 3
      releases = List.first(result)["releases"]

      for release <- releases do
        assert length(Map.keys(release)) == 3
        assert Map.has_key?(release, "url")
        assert Map.has_key?(release, "version")
        assert Map.has_key?(release, "has_docs")
      end

      conn = get(build_conn(), "api/packages?search=#{package1.name}")
      result = json_response(conn, 200)
      assert length(result) == 1

      conn = get(build_conn(), "api/packages?search=name%3A#{package1.name}*")
      result = json_response(conn, 200)
      assert length(result) == 1

      conn = get(build_conn(), "api/packages?page=1")
      result = json_response(conn, 200)
      assert length(result) == 3

      conn = get(build_conn(), "api/packages?page=2")
      result = json_response(conn, 200)
      assert length(result) == 0
    end

    test "sort order", %{package1: package1, package2: package2} do
      conn = get(build_conn(), "api/packages?sort=updated_at")
      result = json_response(conn, 200)
      assert hd(result)["name"] == package2.name

      conn = get(build_conn(), "api/packages?sort=inserted_at")
      result = json_response(conn, 200)
      assert hd(result)["name"] == package1.name
    end

    test "show private packages", %{user: user, package3: package3} do
      result =
        build_conn()
        # TODO: change to web_login/api_login helper
        |> put_req_header("authorization", key_for(user))
        |> get("api/packages")
        |> json_response(200)

      assert length(result) == 4
      assert package3.name in Enum.map(result, & &1["name"])
    end

    test "show private packages in organization", %{
      user: user,
      organization: organization,
      package3: package3
    } do
      result =
        build_conn()
        # TODO: change to web_login/api_login helper
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{organization.name}/packages")
        |> json_response(200)

      assert length(result) == 1
      assert package3.name in Enum.map(result, & &1["name"])
    end

    test "show private packages in organization with service account", %{
      organization: organization,
      package3: package3
    } do
      user = insert(:user, service: true)

      result =
        build_conn()
        # TODO: change to web_login/api_login helper
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{organization.name}/packages")
        |> json_response(200)

      assert length(result) == 1
      assert package3.name in Enum.map(result, & &1["name"])
    end

    test "show private packages in organization authorizes", %{
      organization: organization,
      unauthorized_user: unauthorized_user
    } do
      build_conn()
      |> get("api/repos/#{organization.name}/packages")
      |> json_response(403)

      build_conn()
      # TODO: change to web_login/api_login helper
      |> put_req_header("authorization", key_for(unauthorized_user))
      |> get("api/repos/#{organization.name}/packages")
      |> json_response(403)
    end
  end

  describe "GET /api/packages/:name" do
    test "get package", %{package1: package1} do
      conn = get(build_conn(), "api/packages/#{package1.name}")
      result = json_response(conn, 200)
      assert result["name"] == package1.name
      assert result["inserted_at"] == "2030-01-01T00:00:00.000000Z"
      # updated_at ISO8601 datetime string should include a Z to indicate UTC
      assert String.slice(result["updated_at"], -1, 1) == "Z"
      assert result["url"] =~ "/api/packages/#{package1.name}"
      assert result["html_url"] =~ "/packages/#{package1.name}"
      assert result["docs_html_url"] =~ "/#{package1.name}"

      release = List.first(result["releases"])
      assert release["url"] =~ "/api/packages/#{package1.name}/releases/0.0.1"
      assert release["version"] == "0.0.1"
    end

    test "get package for non namespaced private organization", %{user: user, package3: package3} do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/packages/#{package3.name}")
      |> json_response(404)
    end

    test "get package for unauthenticated private organization", %{
      organization: organization,
      package3: package3
    } do
      build_conn()
      |> get("api/repos/#{organization.name}/packages/#{package3.name}")
      |> json_response(403)
    end

    test "get package returns 403 for unknown organization", %{package1: package1} do
      build_conn()
      |> get("api/repos/UNKNOWN_REPOSITORY/packages/#{package1.name}")
      |> json_response(403)
    end

    test "get package returns 403 for unknown package if you are not authorized", %{
      organization: organization
    } do
      build_conn()
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE")
      |> json_response(403)
    end

    test "get package returns 404 for unknown package if you are authorized", %{
      user: user,
      organization: organization
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE")
      |> json_response(404)
    end

    test "get package for authenticated private organization", %{
      user: user,
      organization: organization,
      package3: package3
    } do
      result =
        build_conn()
        |> put_req_header("authorization", key_for(user))
        |> get("api/repos/#{organization.name}/packages/#{package3.name}")
        |> json_response(200)

      assert result["name"] == package3.name
      assert result["repository"] == organization.name
      assert result["url"] =~ "/api/repos/#{organization.name}/packages/#{package3.name}"
      assert result["html_url"] =~ "/packages/#{organization.name}/#{package3.name}"
    end

    test "get package with retired versions", %{package4: package4} do
      conn = get(build_conn(), "api/packages/#{package4.name}")
      result = json_response(conn, 200)

      assert result["retirements"] == %{
               "0.0.1" => %{"message" => "not backward compatible", "reason" => "other"}
             }
    end
  end
end

defmodule Hexpm.Web.API.RetirementControllerTest do
  use Hexpm.ConnCase, async: true

  setup do
    user = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, owner: user)])
    insert(:release, package: package, version: "1.0.0")
    %{user: user, package: package}
  end

  test "retire and unretire release", %{user: user, package: package} do
    params = %{"reason" => "security", "message" => "See CVE-NNNN"}
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> post("api/packages/#{package.name}/releases/1.0.0/retire", params)
    |> response(204)

    release = Hexpm.Repository.Releases.get(package, "1.0.0")
    assert release.retirement
    assert release.retirement.reason == "security"
    assert release.retirement.message == "See CVE-NNNN"

    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/packages/#{package.name}/releases/1.0.0/retire")
    |> response(204)

    release = Hexpm.Repository.Releases.get(package, "1.0.0")
    refute release.retirement
  end
end

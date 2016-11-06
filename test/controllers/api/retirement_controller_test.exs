defmodule HexWeb.API.RetirementControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    package = Package.build(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal aritmetic for Elixir."})) |> HexWeb.Repo.insert!
    release = Release.build(package, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    %{user: user, package: package, release: release}
  end

  test "retire and unretire release", c do
    params = %{"status" => "security", "message" => "See CVE-NNNN"}
    conn = build_conn()
           |> put_req_header("authorization", key_for(c.user))
           |> post("api/packages/#{c.package.name}/releases/#{c.release.version}/retire", params)
    assert conn.status == 204

    release = HexWeb.Releases.get(c.package, c.release.version)
    assert release.retirement
    assert release.retirement.status == "security"
    assert release.retirement.message == "See CVE-NNNN"

    conn = build_conn()
           |> put_req_header("authorization", key_for(c.user))
           |> delete("api/packages/#{c.package.name}/releases/#{c.release.version}/retire")
    assert conn.status == 204

    release = HexWeb.Releases.get(c.package, c.release.version)
    refute release.retirement
  end
end

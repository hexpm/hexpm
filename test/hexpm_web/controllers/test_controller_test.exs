defmodule HexpmWeb.TestControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "GET /repo/names returns stored object" do
    Hexpm.Store.put(:repo_bucket, "names", "DATA", [])
    conn = get(build_conn(), "/repo/names")
    assert response(conn, 200) == "DATA"
  end

  test "GET /repo/versions returns stored object" do
    Hexpm.Store.put(:repo_bucket, "versions", "DATA", [])
    conn = get(build_conn(), "/repo/versions")
    assert response(conn, 200) == "DATA"
  end

  test "GET /repo/installs/hex-1.x.csv returns 200" do
    conn = get(build_conn(), "/repo/installs/hex-1.x.csv")
    assert conn.status == 200
  end

  test "GET /repo/packages/:package returns stored object" do
    Hexpm.Store.put(:repo_bucket, "packages/foo", "PKG", [])
    conn = get(build_conn(), "/repo/packages/foo")
    assert response(conn, 200) == "PKG"
  end

  test "GET /repo/repos/:repository/packages/:package returns stored object" do
    Hexpm.Store.put(:repo_bucket, "repos/acme/packages/foo", "PKG", [])
    conn = get(build_conn(), "/repo/repos/acme/packages/foo")
    assert response(conn, 200) == "PKG"
  end

  test "GET /repo/tarballs/:ball returns stored object" do
    Hexpm.Store.put(:repo_bucket, "tarballs/foo-1.0.0.tar", "TARBALL", [])
    conn = get(build_conn(), "/repo/tarballs/foo-1.0.0.tar")
    assert response(conn, 200) == "TARBALL"
  end

  test "GET /repo/repos/:repository/tarballs/:ball returns stored object" do
    Hexpm.Store.put(:repo_bucket, "repos/acme/tarballs/foo-1.0.0.tar", "TARBALL", [])
    conn = get(build_conn(), "/repo/repos/acme/tarballs/foo-1.0.0.tar")
    assert response(conn, 200) == "TARBALL"
  end

  test "POST /api/repo creates organization and returns 204" do
    user = insert(:user)
    org_name = "org-" <> Fake.sequence(:username)

    conn =
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> json_post("/api/repo", %{"name" => org_name})

    assert conn.status == 204
  end
end

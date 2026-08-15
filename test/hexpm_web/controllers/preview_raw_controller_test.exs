defmodule HexpmWeb.PreviewRawControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    repository = insert(:repository)
    user = insert(:user)
    insert(:organization_user, user: user, organization: repository.organization)
    package = insert(:package, repository_id: repository.id, name: "private_raw")
    insert(:release, package: package, version: "1.0.0")

    files = [
      {"lib/raw.ex", "defmodule Raw do\nend\n"},
      {"index.html", "<script>alert(1)</script>"},
      {"binary.bin", <<0xFF, 0xFE, 0x00>>}
    ]

    prefix = "repos/#{repository.name}/"

    Hexpm.Store.put(
      :preview_bucket,
      "#{prefix}file_lists/#{package.name}-1.0.0.json",
      JSON.encode!(Enum.map(files, &elem(&1, 0)))
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(
        :preview_bucket,
        "#{prefix}files/#{package.name}/1.0.0/#{filename}",
        contents
      )
    end

    %{repository: repository, package: package, user: user}
  end

  test "serves text files as inline plain text with hardened headers", %{
    repository: repository,
    package: package,
    user: user
  } do
    conn =
      build_conn()
      |> test_login(user)
      |> get("/packages/#{repository.name}/#{package.name}/1.0.0/raw/lib/raw.ex")

    assert conn.status == 200
    assert conn.resp_body == "defmodule Raw do\nend\n"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="raw.ex")]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox; default-src 'none'"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "never serves HTML files with an HTML content type", %{
    repository: repository,
    package: package,
    user: user
  } do
    conn =
      build_conn()
      |> test_login(user)
      |> get("/packages/#{repository.name}/#{package.name}/1.0.0/raw/index.html")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end

  test "serves binary files as octet-stream attachments", %{
    repository: repository,
    package: package,
    user: user
  } do
    conn =
      build_conn()
      |> test_login(user)
      |> get("/packages/#{repository.name}/#{package.name}/1.0.0/raw/binary.bin")

    assert conn.status == 200
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/octet-stream"
    assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="binary.bin")]
  end

  test "returns 404 for non-members, anonymous users, and unknown files", %{
    repository: repository,
    package: package,
    user: user
  } do
    other_user = insert(:user)

    conn = get(build_conn(), "/packages/#{repository.name}/#{package.name}/1.0.0/raw/lib/raw.ex")
    assert conn.status == 404

    conn =
      build_conn()
      |> test_login(other_user)
      |> get("/packages/#{repository.name}/#{package.name}/1.0.0/raw/lib/raw.ex")

    assert conn.status == 404

    conn =
      build_conn()
      |> test_login(user)
      |> get("/packages/#{repository.name}/#{package.name}/1.0.0/raw/unlisted.ex")

    assert conn.status == 404

    conn =
      build_conn()
      |> test_login(user)
      |> get("/packages/#{repository.name}/#{package.name}/2.0.0/raw/lib/raw.ex")

    assert conn.status == 404
  end
end

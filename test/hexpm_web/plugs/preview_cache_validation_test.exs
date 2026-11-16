defmodule HexpmWeb.Plugs.PreviewCacheValidationTest do
  use HexpmWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Hexpm.Repo
  alias Hexpm.Repository.Release

  @path "/packages/cached_preview/1.0.0/files/README.md"

  setup do
    package = put_release("cached_preview", "1.0.0", [{"README.md", "readme"}])
    %{conn: build_conn(), package: package}
  end

  test "a request without a session cookie gets a validator", %{conn: conn} do
    conn = get(conn, @path)

    assert conn.status == 200
    assert [~s(W/") <> _] = get_resp_header(conn, "etag")
    assert get_resp_header(conn, "cache-control") == ["private, max-age=86400"]
    assert [vary] = get_resp_header(conn, "vary")
    assert "cookie" in String.split(vary, ", ")
  end

  test "an unchanged page is answered with 304", %{conn: conn} do
    [etag] = get_resp_header(get(conn, @path), "etag")

    conn =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get(@path)

    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "etag") == [etag]

    conn =
      build_conn()
      |> put_req_header("if-none-match", ~s(W/"other", #{etag}))
      |> get(@path)

    assert conn.status == 304
  end

  test "the validator changes with the package's releases", %{conn: conn, package: package} do
    [etag] = get_resp_header(get(conn, @path), "etag")

    put_release("cached_preview", "2.0.0", [{"README.md", "two"}], package)
    [published] = get_resp_header(get(build_conn(), @path), "etag")
    refute published == etag

    Repo.update_all(
      from(r in Release, where: r.package_id == ^package.id and r.version == "1.0.0"),
      set: [updated_at: ~U[2030-01-01 00:00:00.000000Z]]
    )

    conn =
      build_conn()
      |> put_req_header("if-none-match", published)
      |> get(@path)

    assert conn.status == 200
    refute get_resp_header(conn, "etag") == [published]
  end

  test "a request with a session cookie always renders the page", %{conn: conn} do
    [etag] = get_resp_header(get(conn, @path), "etag")

    conn =
      build_conn()
      |> put_req_cookie(HexpmWeb.Endpoint.session_cookie(), "session")
      |> put_req_header("if-none-match", etag)
      |> get(@path)

    assert conn.status == 200
    assert get_resp_header(conn, "etag") == []
    assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
  end

  test "a signed in user always gets a rendered page", %{conn: conn} do
    conn =
      conn
      |> test_login(insert(:user))
      |> get(@path)

    assert conn.status == 200
    assert get_resp_header(conn, "etag") == []
  end

  test "a redirect gets no validator", %{conn: conn} do
    conn = get(conn, "/packages/cached_preview/1.0.0/files/missing.ex?fallback=default")

    assert redirected_to(conn) == @path
    assert get_resp_header(conn, "etag") == []
  end

  test "a private package's files get no validator", %{conn: conn} do
    repository = insert(:repository)
    user = insert(:user)
    insert(:organization_user, user: user, organization: repository.organization)
    package = insert(:package, repository_id: repository.id, name: "cached_private")
    insert(:release, package: package, version: "1.0.0")

    Hexpm.Store.put(
      :preview_bucket,
      "repos/#{repository.name}/file_lists/cached_private-1.0.0.json",
      Jason.encode!(["mix.exs"])
    )

    Hexpm.Store.put(
      :preview_bucket,
      "repos/#{repository.name}/files/cached_private/1.0.0/mix.exs",
      "mix"
    )

    conn =
      conn
      |> test_login(user)
      |> get("/packages/#{repository.name}/cached_private/1.0.0/files/mix.exs")

    assert conn.status == 200
    assert get_resp_header(conn, "etag") == []

    conn = get(build_conn(), "/packages/hexpm/cached_preview/1.0.0/files/README.md")
    assert conn.status == 200
    assert [_] = get_resp_header(conn, "etag")
  end

  defp put_release(package_name, version, files, package \\ nil) do
    package = package || insert(:package, name: package_name)
    insert(:release, package: package, version: version)

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/#{package_name}-#{version}.json",
      Jason.encode!(Enum.map(files, &elem(&1, 0)))
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(:preview_bucket, "files/#{package_name}/#{version}/#{filename}", contents)
    end

    package
  end
end

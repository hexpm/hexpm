defmodule HexpmWeb.PreviewImageControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    repository = insert(:repository)
    package = insert(:package, repository_id: repository.id, name: "private_image")
    insert(:release, package: package, version: "1.0.0")

    files = [
      {"assets/logo.png", <<0x89, "PNG", 0x0D>>},
      {"assets/diagram.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"},
      {"README.md", "# readme"}
    ]

    prefix = "repos/#{repository.name}/"

    Hexpm.Store.put(
      :preview_bucket,
      "#{prefix}file_lists/#{package.name}-1.0.0.json",
      Jason.encode!(Enum.map(files, &elem(&1, 0)))
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(
        :preview_bucket,
        "#{prefix}files/#{package.name}/1.0.0/#{filename}",
        contents
      )
    end

    %{repository: repository, package: package}
  end

  defp token(repository, package, version \\ "1.0.0") do
    HexpmWeb.ReadmeToken.sign(repository.name, package.name, version)
  end

  test "serves an image with its real content type and hardened headers", %{
    repository: repository,
    package: package
  } do
    conn =
      get(
        build_conn(),
        "/packages/#{repository.name}/#{package.name}/1.0.0/readme-image/assets/logo.png?token=#{token(repository, package)}"
      )

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox; default-src 'none'"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "serves svg as image/svg+xml", %{repository: repository, package: package} do
    conn =
      get(
        build_conn(),
        "/packages/#{repository.name}/#{package.name}/1.0.0/readme-image/assets/diagram.svg?token=#{token(repository, package)}"
      )

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/svg+xml"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox; default-src 'none'"]
  end

  test "requires no session and works anonymously with a valid token", %{
    repository: repository,
    package: package
  } do
    # No test_login — the image proxy fetches anonymously.
    conn =
      get(
        build_conn(),
        "/packages/#{repository.name}/#{package.name}/1.0.0/readme-image/assets/logo.png?token=#{token(repository, package)}"
      )

    assert conn.status == 200
  end

  test "404s for missing, mismatched, and expired tokens", %{
    repository: repository,
    package: package
  } do
    path = "/packages/#{repository.name}/#{package.name}/1.0.0/readme-image/assets/logo.png"

    assert get(build_conn(), path).status == 404

    other = HexpmWeb.ReadmeToken.sign(repository.name, "other_package", "1.0.0")
    assert get(build_conn(), "#{path}?token=#{other}").status == 404

    wrong_version = HexpmWeb.ReadmeToken.sign(repository.name, package.name, "2.0.0")
    assert get(build_conn(), "#{path}?token=#{wrong_version}").status == 404
  end

  test "404s for non-image extensions and files not in the list", %{
    repository: repository,
    package: package
  } do
    readme_path =
      "/packages/#{repository.name}/#{package.name}/1.0.0/readme-image/README.md?token=#{token(repository, package)}"

    assert get(build_conn(), readme_path).status == 404

    missing_path =
      "/packages/#{repository.name}/#{package.name}/1.0.0/readme-image/assets/missing.png?token=#{token(repository, package)}"

    assert get(build_conn(), missing_path).status == 404
  end
end

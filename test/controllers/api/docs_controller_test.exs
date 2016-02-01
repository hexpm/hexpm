defmodule HexWeb.API.DocsControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    :ok
  end

  test "release docs" do
    user           = User.get(username: "eric")
    {:ok, phoenix} = Package.create(user, pkg_meta(%{name: "phoenix", description: "Web framework"}))
    {:ok, _}       = Release.create(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
    {:ok, _}       = Release.create(phoenix, rel_meta(%{version: "0.0.2", app: "phoenix"}), "")

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'index.html', "HEYO"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/phoenix/releases/0.0.1/docs", body)
    assert conn.status == 201
    assert Release.get(phoenix, "0.0.1").has_docs

    conn = get conn(), "docs/phoenix/index.html"
    assert conn.status == 200
    assert conn.resp_body == "HEYO"

    conn = get conn(), "docs/phoenix/0.0.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "HEYO"

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'index.html', "NOPE"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/phoenix/releases/0.0.2/docs", body)
    assert conn.status == 201

    conn = get conn(), "docs/phoenix/index.html"
    assert conn.status == 200
    assert conn.resp_body == "NOPE"

    conn = get conn(), "docs/phoenix/0.0.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "HEYO"
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  test "delete release with docs" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end

    user        = User.get(username: "eric")
    {:ok, ecto} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    {:ok, _}    = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'index.html', "HEYO"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases/0.0.1/docs", body)

    assert conn.status == 201
    assert Release.get(ecto, "0.0.1").has_docs

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/packages/ecto/releases/0.0.1")
    assert conn.status == 204

    # Check release was deleted
    refute Release.get(ecto, "0.0.1")

    # Check docs were deleted
    conn = get conn(), "api/packages/ecto/releases/0.0.1/docs"
    assert conn.status in 400..499

    conn = get conn(), "docs/ecto/0.0.1/index.html"
    assert conn.status in 400..499
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  test "dont allow version directories in docs" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end

    user        = User.get(username: "eric")
    {:ok, ecto} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    {:ok, _}    = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")

    path = Path.join("tmp", "release-docs.tar.gz")
    files = [{'1.2.3', "HEYO"}]
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    body = File.read!(path)

    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases/0.0.1/docs", body)

    assert conn.status == 422
    assert %{"errors" => %{"tar" => "directory name not allowed to match a semver version"}} =
           Poison.decode!(conn.resp_body)
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end
end

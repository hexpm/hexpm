defmodule HexWeb.API.DocsControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    |> HexWeb.Repo.insert!
    :ok
  end

  @tag :integration
  test "release docs" do
    user           = HexWeb.Repo.get_by!(User, username: "eric")
    {:ok, phoenix} = Package.create(user, pkg_meta(%{name: "phoenix", description: "Web framework"}))
    {:ok, _}       = Release.create(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "")
    {:ok, _}       = Release.create(phoenix, rel_meta(%{version: "0.0.2", app: "phoenix"}), "")

    body = create_tarball([{'index.html', "HEYO"}])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/phoenix/releases/0.0.1/docs", body)
    assert conn.status == 201
    assert HexWeb.Repo.get_by!(assoc(phoenix, :releases), version: "0.0.1").has_docs

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "docs.publish"
    assert %{"package" => %{"name" => "phoenix"}, "release" => %{"version" => "0.0.1"}} = log.params

    conn = get conn(), "docs/phoenix/index.html"
    assert conn.status == 200
    assert conn.resp_body == "HEYO"

    conn = get conn(), "docs/phoenix/0.0.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "HEYO"

    body = create_tarball([{'index.html', "NOPE"}])
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

    conn = get conn(), "docs/sitemap.xml"
    assert conn.status == 200
    assert conn.resp_body =~ "https://hexdocs.pm/phoenix"
  end

  @tag :integration
  test "release beta docs" do
    user        = HexWeb.Repo.get_by!(User, username: "eric")
    {:ok, plug} = Package.create(user, pkg_meta(%{name: "plug", description: "Web framework"}))
    {:ok, _}    = Release.create(plug, rel_meta(%{version: "0.0.1-beta.1", app: "plug"}), "")
    {:ok, _}    = Release.create(plug, rel_meta(%{version: "0.5.0", app: "plug"}), "")
    {:ok, _}    = Release.create(plug, rel_meta(%{version: "1.0.0-beta.1", app: "plug"}), "")

    body = create_tarball([{'index.html', "plug v0.0.1-beta.1"}])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/plug/releases/0.0.1-beta.1/docs", body)
    assert conn.status == 201
    assert HexWeb.Repo.get_by!(assoc(plug, :releases), version: "0.0.1-beta.1").has_docs

    conn = get conn(), "docs/plug/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v0.0.1-beta.1"

    body = create_tarball([{'index.html', "plug v0.5.0"}])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/plug/releases/0.5.0/docs", body)
    assert conn.status == 201

    conn = get conn(), "docs/plug/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v0.5.0"

    body = create_tarball([{'index.html', "plug v1.0.0-beta.1"}])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/plug/releases/1.0.0-beta.1/docs", body)
    assert conn.status == 201

    conn = get conn(), "docs/plug/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v0.5.0"

    conn = get conn(), "docs/plug/1.0.0-beta.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v1.0.0-beta.1"
  end

  test "delete release with docs" do
    user        = HexWeb.Repo.get_by!(User, username: "eric")
    {:ok, ecto} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    {:ok, _}    = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")

    body = create_tarball([{'index.html', "HEYO"}])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases/0.0.1/docs", body)

    assert conn.status == 201
    assert HexWeb.Repo.get_by!(assoc(ecto, :releases), version: "0.0.1").has_docs

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/packages/ecto/releases/0.0.1")
    assert conn.status == 204

    # Check release was deleted
    refute HexWeb.Repo.get_by(assoc(ecto, :releases), version: "0.0.1")

    # Check docs were deleted
    assert_raise Ecto.NoResultsError, fn ->
      get conn(), "api/packages/ecto/releases/0.0.1/docs"
    end

    conn = get conn(), "docs/ecto/0.0.1/index.html"
    assert conn.status in 400..499
  end

  @tag :integration
  test "delete docs" do
    user        = HexWeb.Repo.get_by!(User, username: "eric")
    {:ok, ecto} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    {:ok, _}    = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")

    body = create_tarball([{'index.html', "HEYO"}])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases/0.0.1/docs", body)

    assert conn.status == 201
    assert HexWeb.Repo.get_by!(assoc(ecto, :releases), version: "0.0.1").has_docs
    assert HexWeb.Repo.one!(HexWeb.AuditLog).action == "docs.publish"

    conn = conn()
           |> put_req_header("authorization", key_for("eric"))
           |> delete("api/packages/ecto/releases/0.0.1/docs")
    assert conn.status == 204

    # Check release was deleted
    refute HexWeb.Repo.get_by(assoc(ecto, :releases), version: "0.0.1").has_docs

    [_, log] = HexWeb.Repo.all(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "docs.revert"
    assert %{"package" => %{"name" => "ecto"}, "release" => %{"version" => "0.0.1"}} = log.params

    # Check docs were deleted
    conn = get conn(), "api/packages/ecto/releases/0.0.1/docs"
    assert conn.status in 400..499

    conn = get conn(), "docs/ecto/0.0.1/index.html"
    assert conn.status in 400..499
  end

  @tag :integration
  test "dont allow version directories in docs" do
    user        = HexWeb.Repo.get_by!(User, username: "eric")
    {:ok, ecto} = Package.create(user, pkg_meta(%{name: "ecto", description: "DSL"}))
    {:ok, _}    = Release.create(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "")

    body = create_tarball([{'1.2.3', "HEYO"}])
    conn = conn()
           |> put_req_header("content-type", "application/octet-stream")
           |> put_req_header("authorization", key_for("eric"))
           |> post("api/packages/ecto/releases/0.0.1/docs", body)

    assert conn.status == 422
    assert %{"errors" => %{"tar" => "directory name not allowed to match a semver version"}} =
           Poison.decode!(conn.resp_body)
  end

  defp create_tarball(files) do
    path = Path.join("tmp", "release-docs.tar.gz")
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    File.read!(path)
  end
end

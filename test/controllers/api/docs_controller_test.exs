defmodule HexWeb.API.DocsControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    {:ok, user: user}
  end

  @tag :integration
  test "release docs", %{user: user} do
    phoenix = Package.build(user, pkg_meta(%{name: "phoenix", description: "Web framework"})) |> HexWeb.Repo.insert!
    Release.build(phoenix, rel_meta(%{version: "0.0.1", app: "phoenix"}), "") |> HexWeb.Repo.insert!
    Release.build(phoenix, rel_meta(%{version: "0.5.0", app: "phoenix"}), "") |> HexWeb.Repo.insert!

    conn = publish_docs(user, phoenix, "0.0.1", [{'index.html', "phoenix v0.0.1"}])
    assert conn.status == 201
    assert HexWeb.Repo.get_by!(assoc(phoenix, :releases), version: "0.0.1").has_docs

    log = HexWeb.Repo.one!(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "docs.publish"
    assert %{"package" => %{"name" => "phoenix"}, "release" => %{"version" => "0.0.1"}} = log.params

    conn = get build_conn(), "docs/phoenix/index.html"
    assert conn.status == 200
    assert conn.resp_body == "phoenix v0.0.1"

    conn = get build_conn(), "docs/phoenix/0.0.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "phoenix v0.0.1"

    conn = publish_docs(user, phoenix, "0.5.0", [{'index.html', "phoenix v0.5.0"}])
    assert conn.status == 201

    conn = get build_conn(), "docs/phoenix/index.html"
    assert conn.status == 200
    assert conn.resp_body == "phoenix v0.5.0"

    conn = get build_conn(), "docs/phoenix/0.0.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "phoenix v0.0.1"

    conn = get build_conn(), "docs/sitemap.xml"
    assert conn.status == 200
    assert conn.resp_body =~ "https://hexdocs.pm/phoenix"

    conn = publish_docs(user, phoenix, "0.0.1", [{'index.html', "phoenix v0.0.1 (updated)"}])
    assert conn.status == 201

    conn = get build_conn(), "docs/phoenix/index.html"
    assert conn.status == 200
    assert conn.resp_body == "phoenix v0.5.0"

    conn = get build_conn(), "docs/phoenix/0.0.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "phoenix v0.0.1 (updated)"
  end

  @tag :integration
  test "release beta docs", %{user: user} do
    plug = Package.build(user, pkg_meta(%{name: "plug", description: "Web framework"})) |> HexWeb.Repo.insert!
    Release.build(plug, rel_meta(%{version: "0.0.1-beta.1", app: "plug"}), "") |> HexWeb.Repo.insert!
    Release.build(plug, rel_meta(%{version: "0.5.0", app: "plug"}), "") |> HexWeb.Repo.insert!
    Release.build(plug, rel_meta(%{version: "1.0.0-beta.1", app: "plug"}), "") |> HexWeb.Repo.insert!

    conn = publish_docs(user, plug, "0.0.1-beta.1", [{'index.html', "plug v0.0.1-beta.1"}])
    assert conn.status == 201
    assert HexWeb.Repo.get_by!(assoc(plug, :releases), version: "0.0.1-beta.1").has_docs

    conn = get build_conn(), "docs/plug/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v0.0.1-beta.1"

    conn = publish_docs(user, plug, "0.5.0", [{'index.html', "plug v0.5.0"}])
    assert conn.status == 201

    conn = get build_conn(), "docs/plug/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v0.5.0"

    conn = publish_docs(user, plug, "1.0.0-beta.1", [{'index.html', "plug v1.0.0-beta.1"}])
    assert conn.status == 201

    conn = get build_conn(), "docs/plug/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v0.5.0"

    conn = get build_conn(), "docs/plug/1.0.0-beta.1/index.html"
    assert conn.status == 200
    assert conn.resp_body == "plug v1.0.0-beta.1"
  end

  @tag isolation: :serializable
  test "delete release with docs" do
    user = HexWeb.Repo.get_by!(User, username: "eric")
    ecto = Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    Release.build(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "") |> HexWeb.Repo.insert!

    conn = publish_docs(user, ecto, "0.0.1", [{'index.html', "ecto v0.0.1"}])
    assert conn.status == 201
    assert HexWeb.Repo.get_by!(assoc(ecto, :releases), version: "0.0.1").has_docs

    conn = revert_release(user, ecto, "0.0.1")
    assert conn.status == 204

    # Check release was deleted
    refute HexWeb.Repo.get_by(assoc(ecto, :releases), version: "0.0.1")

    # Check docs were deleted
    conn = get build_conn(), "api/packages/ecto/releases/0.0.1/docs"
    assert conn.status in 400..499

    conn = get build_conn(), "docs/ecto/0.0.1/index.html"
    assert conn.status in 400..499
  end

  @tag :integration
  test "delete docs", %{user: user} do
    ecto = Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    Release.build(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "") |> HexWeb.Repo.insert!
    Release.build(ecto, rel_meta(%{version: "0.5.0", app: "ecto"}), "") |> HexWeb.Repo.insert!
    Release.build(ecto, rel_meta(%{version: "2.0.0", app: "ecto"}), "") |> HexWeb.Repo.insert!

    conn = publish_docs(user, ecto, "0.0.1", [{'index.html', "ecto v0.0.1"}])
    assert conn.status == 201
    conn = publish_docs(user, ecto, "0.5.0", [{'index.html', "ecto v0.5.0"}])
    assert conn.status == 201
    conn = publish_docs(user, ecto, "2.0.0", [{'index.html', "ecto v2.0.0"}])
    assert conn.status == 201

    # Revert middle release 
    conn = revert_docs(user, ecto, "0.5.0")
    assert conn.status == 204

    # Check release was deleted
    refute HexWeb.Repo.get_by(assoc(ecto, :releases), version: "0.5.0").has_docs

    [%{action: "docs.publish"}, %{action: "docs.publish"}, %{action: "docs.publish"}, log] =
      HexWeb.Repo.all(HexWeb.AuditLog)
    assert log.actor_id == user.id
    assert log.action == "docs.revert"
    assert %{"package" => %{"name" => "ecto"}, "release" => %{"version" => "0.5.0"}} = log.params

    # Check docs were deleted
    conn = get build_conn(), "api/packages/ecto/releases/0.5.0/docs"
    assert conn.status in 400..499

    conn = get build_conn(), "docs/ecto/0.5.0/index.html"
    assert conn.status in 400..499

    conn = get build_conn(), "docs/ecto/index.html"
    assert conn.status == 200
    assert conn.resp_body == "ecto v2.0.0"

    # Revert latest release
    conn = revert_docs(user, ecto, "2.0.0")
    assert conn.status == 204

    # Check release was deleted
    refute HexWeb.Repo.get_by(assoc(ecto, :releases), version: "2.0.0").has_docs

    # Check docs were deleted
    conn = get build_conn(), "api/packages/ecto/releases/2.0.0/docs"
    assert conn.status in 400..499

    conn = get build_conn(), "docs/ecto/2.0.0/index.html"
    assert conn.status in 400..499

    # TODO: update top-level docs to the next-to-last version
    conn = get build_conn(), "docs/ecto/index.html"
    assert conn.status == 200
    assert conn.resp_body == "ecto v2.0.0"

    # Revert remaining release
    conn = revert_docs(user, ecto, "0.0.1")
    assert conn.status == 204

    # Check release was deleted
    refute HexWeb.Repo.get_by(assoc(ecto, :releases), version: "0.0.1").has_docs

    # Check docs were deleted
    conn = get build_conn(), "api/packages/ecto/releases/0.0.1/docs"
    assert conn.status in 400..499

    conn = get build_conn(), "docs/ecto/0.0.1/index.html"
    assert conn.status in 400..499

    # TODO: deleting last version should remove top-level docs
    conn = get build_conn(), "docs/ecto/index.html"
    assert conn.status == 200
    assert conn.resp_body == "ecto v2.0.0"
  end

  @tag :integration
  test "dont allow version directories in docs", %{user: user} do
    ecto = Package.build(user, pkg_meta(%{name: "ecto", description: "DSL"})) |> HexWeb.Repo.insert!
    Release.build(ecto, rel_meta(%{version: "0.0.1", app: "ecto"}), "") |> HexWeb.Repo.insert!

    conn = publish_docs(user, ecto, "0.0.1", [{'1.2.3', "ecto v0.0.1"}])
    assert conn.status == 422
    assert %{"errors" => %{"tar" => "directory name not allowed to match a semver version"}} =
           Poison.decode!(conn.resp_body)
  end

  defp publish_docs(user, %Package{name: name}, version, files) do
    body = create_tarball(files)

    build_conn()
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", key_for(user))
    |> post("api/packages/#{name}/releases/#{version}/docs", body)
  end

  def revert_docs(user, %Package{name: name}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/packages/#{name}/releases/#{version}/docs")
  end

  def revert_release(user, %Package{name: name}, version) do
    build_conn()
    |> put_req_header("authorization", key_for(user))
    |> delete("api/packages/#{name}/releases/#{version}")
  end

  defp create_tarball(files) do
    path = Path.join("tmp", "release-docs.tar.gz")
    :ok = :erl_tar.create(String.to_char_list(path), files, [:compressed])
    File.read!(path)
  end
end

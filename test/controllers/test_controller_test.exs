defmodule HexWeb.TestControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  setup do
    user = User.build(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    Package.build(user, pkg_meta(%{name: "postgrex", description: "PostgreSQL driver for Elixir."})) |> HexWeb.Repo.insert!
    pkg = Package.build(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> HexWeb.Repo.insert!
    Release.build(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    :ok
  end

  test "fetch registry" do
    RegistryBuilder.partial_build(:v1)
    conn = get(build_conn(), "repo/registry.ets.gz")
    assert conn.status in 200..399
  end

  # test "fetch tarball" do
  #   conn = get build_conn(), "tarballs/decimal-0.0.1.tar"
  #   assert conn.status == 200
  # end
end

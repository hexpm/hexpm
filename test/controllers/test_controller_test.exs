defmodule HexWeb.TestControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  setup do
    user       = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    Package.create(user, pkg_meta(%{name: "postgrex", description: "PostgreSQL driver for Elixir."})) |> HexWeb.Repo.insert!
    pkg = Package.create(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> HexWeb.Repo.insert!
    Release.create(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    :ok
  end

  test "fetch registry" do
    RegistryBuilder.rebuild
    conn = get conn(), "registry.ets.gz"
    assert conn.status in 200..399
  end

  # test "fetch tarball" do
  #   conn = get conn(), "tarballs/decimal-0.0.1.tar"
  #   assert conn.status == 200
  # end
end

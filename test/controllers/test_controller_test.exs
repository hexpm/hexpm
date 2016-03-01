defmodule HexWeb.TestControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  setup do
    user       = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    {:ok, _}   = Package.create(user, pkg_meta(%{name: "postgrex", description: "PostgreSQL driver for Elixir."}))
    {:ok, pkg} = Package.create(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."}))
    {:ok, _}   = Release.create(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
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

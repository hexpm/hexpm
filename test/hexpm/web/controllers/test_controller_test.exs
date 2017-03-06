defmodule Hexpm.TestControllerTest do
  use Hexpm.ConnCase, async: true

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release
  alias Hexpm.Repository.RegistryBuilder

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    Package.build(user, pkg_meta(%{name: "postgrex", description: "PostgreSQL driver for Elixir."})) |> Hexpm.Repo.insert!
    pkg = Package.build(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> Hexpm.Repo.insert!
    Release.build(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> Hexpm.Repo.insert!
    :ok
  end

  test "fetch registry" do
    RegistryBuilder.partial_build(:v1)
    conn = get(build_conn(), "repo/registry.ets.gz")
    assert conn.status in 200..399
  end
end

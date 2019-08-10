defmodule HexpmWeb.TestControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Repository.{RegistryBuilder, Repository}

  setup do
    insert(:package, releases: [build(:release)])
    :ok
  end

  test "fetch registry" do
    RegistryBuilder.v1_repository(Repository.hexpm())
    conn = get(build_conn(), "repo/registry.ets.gz")
    assert conn.status in 200..399
  end
end

defmodule HexpmWeb.TestControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Repository.{RegistryBuilder, Repository}

  setup do
    insert(:package, releases: [build(:release)])
    :ok
  end

  test "fetch registry" do
    RegistryBuilder.partial_build({:v1, Repository.hexpm()})
    conn = get(build_conn(), "repo/registry.ets.gz")
    assert conn.status in 200..399
  end
end

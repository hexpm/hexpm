defmodule Hexpm.Web.TestControllerTest do
  use Hexpm.ConnCase, async: true

  alias Hexpm.Repository.RegistryBuilder

  setup do
    insert(:package, releases: [build(:release)])
    :ok
  end

  test "fetch registry" do
    RegistryBuilder.partial_build(:v1)
    conn = get(build_conn(), "repo/registry.ets.gz")
    assert conn.status in 200..399
  end
end

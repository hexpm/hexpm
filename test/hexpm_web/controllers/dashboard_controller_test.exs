defmodule HexpmWeb.DashboardControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  setup do
    %{
      user: insert(:user)
    }
  end

  test "show index", context do
    conn =
      build_conn()
      |> test_login(context.user)
      |> get("dashboard")

    assert redirected_to(conn) == "/dashboard/profile"
  end

  test "requires login" do
    conn = get(build_conn(), "dashboard")
    assert redirected_to(conn) == "/login?return=dashboard"
  end
end

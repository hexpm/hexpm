defmodule HexpmWeb.Live.ValidateParamsTest do
  use HexpmWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "a mount whose params hold a NUL byte is sent to the home page" do
    assert {:halt, socket} =
             HexpmWeb.Live.ValidateParams.on_mount(
               :default,
               %{"package" => "a\0b"},
               %{},
               %Phoenix.LiveView.Socket{}
             )

    assert {:redirect, %{to: "/"}} = socket.redirected
  end

  test "a patch whose params hold a NUL byte is sent to the home page" do
    {:ok, view, _html} = live(build_conn(), ~p"/packages")

    assert {:error, {:redirect, %{to: "/"}}} = render_patch(view, "/packages?search=a%00b")
  end
end

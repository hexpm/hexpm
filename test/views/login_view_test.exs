defmodule HexWeb.LoginViewTest do
  use HexWeb.ConnCase, async: true

  import Phoenix.ConnTest, except: [conn: 0]
  import Phoenix.View

  test "renders show.html" do
    assert render_to_string(HexWeb.LoginView, "show.html", conn: build_conn(), return: nil) =~ "Log in"
  end
end

defmodule HexWeb.ErrorViewTest do
  use HexWeb.ConnCase, async: true
  import Phoenix.ConnTest, except: [conn: 0]

  import Phoenix.View

  test "renders 404.html" do
    assert render_to_string(HexWeb.ErrorView, "404.html", conn: conn()) =~
           "Page not found"
  end

  test "render 500.html" do
    assert render_to_string(HexWeb.ErrorView, "500.html", conn: conn()) =~
           "Internal server error"
  end

  test "render any other" do
    render_to_string(HexWeb.ErrorView, "505.html", conn: conn())
  end

  defp conn do
    put_in(build_conn().private[:phoenix_flash], %{})
  end
end

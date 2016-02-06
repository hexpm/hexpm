defmodule HexWeb.ErrorViewTest do
  use HexWeb.ConnCase, async: true

  import Phoenix.View

  test "renders 404.html" do
    assert render_to_string(HexWeb.ErrorView, "404.html", []) =~
           "Page not found"
  end

  test "render 500.html" do
    assert render_to_string(HexWeb.ErrorView, "500.html", []) =~
           "Internal server error"
  end

  test "render any other" do
    render_to_string(HexWeb.ErrorView, "505.html", [])
  end
end

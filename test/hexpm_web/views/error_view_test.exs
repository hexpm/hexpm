defmodule HexpmWeb.ErrorViewTest do
  use HexpmWeb.ConnCase, async: true
  import Phoenix.ConnTest, except: [conn: 0]

  import Phoenix.View

  test "renders 400.html" do
    assert render_to_string(HexpmWeb.ErrorView, "400.html", conn: conn()) =~ "Bad request"
  end

  test "renders 404.html" do
    assert render_to_string(HexpmWeb.ErrorView, "404.html", conn: conn()) =~ "Page not found"
  end

  test "renders 408.html" do
    assert render_to_string(HexpmWeb.ErrorView, "408.html", conn: conn()) =~ "Request timeout"
  end

  test "renders 413.html" do
    assert render_to_string(HexpmWeb.ErrorView, "413.html", conn: conn()) =~ "Payload too large"
  end

  test "renders 415.html" do
    assert render_to_string(HexpmWeb.ErrorView, "415.html", conn: conn()) =~
             "Unsupported media type"
  end

  test "renders 422.html" do
    assert render_to_string(HexpmWeb.ErrorView, "422.html", conn: conn()) =~ "Validation error(s)"
  end

  test "render 500.html" do
    assert render_to_string(HexpmWeb.ErrorView, "500.html", conn: conn()) =~
             "Internal server error"
  end

  test "render any other" do
    render_to_string(HexpmWeb.ErrorView, "505.html", conn: conn())
  end

  defp conn() do
    put_in(build_conn().private[:phoenix_flash], %{})
  end
end

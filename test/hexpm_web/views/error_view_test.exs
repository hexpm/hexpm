defmodule HexpmWeb.ErrorViewTest do
  use HexpmWeb.ConnCase, async: true
  import Phoenix.ConnTest, except: [conn: 0]

  import Phoenix.View

  test "renders 400.html" do
    assert render_to_string(HexpmWeb.ErrorView, "400.html", assigns()) =~ "Bad request"
  end

  test "renders 404.html" do
    assert render_to_string(HexpmWeb.ErrorView, "404.html", assigns()) =~ "Page not found"
  end

  test "renders 408.html" do
    assert render_to_string(HexpmWeb.ErrorView, "408.html", assigns()) =~ "Request timeout"
  end

  test "renders 413.html" do
    assert render_to_string(HexpmWeb.ErrorView, "413.html", assigns()) =~ "Payload too large"
  end

  test "renders 415.html" do
    assert render_to_string(HexpmWeb.ErrorView, "415.html", assigns()) =~
             "Unsupported media type"
  end

  test "renders 422.html" do
    assert render_to_string(HexpmWeb.ErrorView, "422.html", assigns()) =~ "Validation error(s)"
  end

  test "render 500.html" do
    assert render_to_string(HexpmWeb.ErrorView, "500.html", assigns()) =~
             "Internal server error"
  end

  test "render any other" do
    render_to_string(HexpmWeb.ErrorView, "505.html", assigns())
  end

  defp assigns() do
    conn =
      build_conn()
      |> put_in([Access.key(:private), :phoenix_flash], %{})

    [conn: conn, script_src_nonce: "test-nonce", style_src_nonce: "test-nonce"]
  end
end

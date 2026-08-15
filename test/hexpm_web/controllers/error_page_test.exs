defmodule HexpmWeb.ErrorPageTest do
  use HexpmWeb.ConnCase, async: true

  test "controller-rendered 404 pages use the site layout" do
    html =
      build_conn()
      |> get("/packages/nothing-here")
      |> html_response(404)

    assert html =~ "Page not found"
    assert html =~ ~s(<nav id="main-navbar")
    assert html =~ ~s(<footer)
    assert html =~ ~s(<!DOCTYPE html>)
  end

  test "endpoint-rendered 404 pages use the site layout" do
    html =
      build_conn()
      |> get("/nothing-here")
      |> html_response(404)

    assert html =~ "Page not found"
    assert html =~ ~s(<nav id="main-navbar")
    assert html =~ ~s(<footer)
    assert html =~ ~s(<!DOCTYPE html>)
  end

  test "endpoint-rendered 500 pages use the site layout" do
    {_status, _headers, html} =
      assert_error_sent 500, fn ->
        get(build_conn(), "/_test/raise")
      end

    assert html =~ "Internal server error"
    assert html =~ ~s(<nav id="main-navbar")
    assert html =~ ~s(<footer)
    assert html =~ ~s(<!DOCTYPE html>)
  end

  test "404 pages render search as a static form, not a LiveView" do
    html =
      build_conn()
      |> get("/nothing-here")
      |> html_response(404)

    assert html =~ ~s(id="nav-search-input")
    refute html =~ "data-phx-session"
  end

  test "json error responses do not use the site layout" do
    body =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> get("/nothing-here")
      |> response(404)

    assert JSON.decode!(body) == %{"message" => "Page not found", "status" => 404}
    refute body =~ ~s(<nav id="main-navbar")
    refute body =~ ~s(<!DOCTYPE html>)
  end
end

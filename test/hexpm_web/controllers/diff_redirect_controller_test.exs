defmodule HexpmWeb.DiffRedirectControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "redirects the Diff host root to packages" do
    conn = request("/")
    assert redirected_to(conn, 301) == "http://localhost:5000/packages"
  end

  test "redirects Diff deep links to the equivalent Hexpm route" do
    conn = request("/diff/ecto/3.0.0..3.1.0?w=1")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/diff/ecto/3.0.0..3.1.0?w=1"
  end

  test "redirects historical short links to their comparison" do
    conn = request("/?diff[]=ecto%3A3.0.0%3A3.1.0")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/diff/ecto/3.0.0..3.1.0"
  end

  test "redirects legacy comparison lists to the diffs index with all comparisons" do
    conn =
      request("/diffs?diffs[]=ecto%3A3.0.0%3A3.1.0&diffs[]=plug%3A1.0.0%3A1.1.0&w=1")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/diffs?" <>
               "diffs%5B%5D=ecto%3A3.0.0%3A3.1.0&diffs%5B%5D=plug%3A1.0.0%3A1.1.0&w=1"
  end

  test "redirects a single legacy comparison straight to its diff" do
    conn = request("/diffs?diffs[]=ecto%3A3.0.0%3A3.1.0&w=1")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/diff/ecto/3.0.0..3.1.0?w=1"
  end

  test "redirects a repo-qualified single comparison to its repo-scoped diff" do
    conn = request("/diffs?diffs[]=acme%2Facme_core%3A1.0.0%3A1.1.0")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/diff/acme/acme_core/1.0.0..1.1.0"
  end

  test "preserves repo qualification when redirecting a comparison list" do
    conn =
      request("/diffs?diffs[]=acme%2Facme_core%3A1.0.0%3A1.1.0&diffs[]=plug%3A1.0.0%3A1.1.0")

    assert redirected_to(conn, 301) ==
             "http://localhost:5000/diffs?" <>
               "diffs%5B%5D=acme%2Facme_core%3A1.0.0%3A1.1.0&diffs%5B%5D=plug%3A1.0.0%3A1.1.0"
  end

  test "redirects unsupported or malformed Diff paths to packages" do
    assert request("/diffs?diffs[]=invalid") |> redirected_to(301) ==
             "http://localhost:5000/packages"

    assert request("/search") |> redirected_to(301) == "http://localhost:5000/packages"
  end

  defp request(path) do
    build_conn()
    |> Map.put(:host, "diff.localhost")
    |> get(path)
  end
end

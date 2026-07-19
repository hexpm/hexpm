defmodule HexpmWeb.DiffControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "lists all requested comparisons with links to each diff" do
    conn = get(build_conn(), "/diffs?diffs[]=ecto%3A3.0.0%3A3.1.0&diffs[]=plug%3A1.0.0%3A1.1.0")
    html = html_response(conn, 200)

    assert html =~ "Package Diffs"
    assert html =~ "/diff/ecto/3.0.0..3.1.0"
    assert html =~ "/diff/plug/1.0.0..1.1.0"
  end

  test "supports the historical diff[] parameter" do
    conn = get(build_conn(), "/diffs?diff[]=ecto%3A3.0.0%3A3.1.0")

    assert html_response(conn, 200) =~ "/diff/ecto/3.0.0..3.1.0"
  end

  test "skips malformed comparisons" do
    conn = get(build_conn(), "/diffs?diffs[]=invalid&diffs[]=ecto%3A3.0.0%3A3.1.0")
    html = html_response(conn, 200)

    assert html =~ "/diff/ecto/3.0.0..3.1.0"
    refute html =~ "invalid"
  end

  test "shows an empty state without comparisons" do
    conn = get(build_conn(), "/diffs")

    assert html_response(conn, 200) =~ "No package diffs available."
  end
end

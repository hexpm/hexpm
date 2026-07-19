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

  test "renders a repo-scoped link for a repo-qualified comparison" do
    conn = get(build_conn(), "/diffs?diffs[]=acme%2Facme_core%3A1.0.0%3A1.1.0")
    html = html_response(conn, 200)

    assert html =~ "/diff/acme/acme_core/1.0.0..1.1.0"
    assert html =~ "/packages/acme/acme_core/1.1.0"
    assert html =~ "acme/acme_core"
  end

  test "renders both public and repo-scoped links in a mixed list" do
    conn =
      get(
        build_conn(),
        "/diffs?diffs[]=acme%2Facme_core%3A1.0.0%3A1.1.0&diffs[]=decimal%3A2.1.1%3A2.3.0"
      )

    html = html_response(conn, 200)

    assert html =~ "/diff/acme/acme_core/1.0.0..1.1.0"
    assert html =~ "/diff/decimal/2.1.1..2.3.0"
  end

  test "skips repo-qualified comparisons with an empty package or extra segments" do
    conn =
      get(
        build_conn(),
        "/diffs?diffs[]=acme%2F%3A1.0.0%3A1.1.0&diffs[]=a%2Fb%2Fc%3A1.0.0%3A1.1.0" <>
          "&diffs[]=ecto%3A3.0.0%3A3.1.0"
      )

    html = html_response(conn, 200)

    assert html =~ "/diff/ecto/3.0.0..3.1.0"
    refute html =~ "1.0.0..1.1.0"
  end

  test "shows an empty state without comparisons" do
    conn = get(build_conn(), "/diffs")

    assert html_response(conn, 200) =~ "No package diffs available."
  end
end

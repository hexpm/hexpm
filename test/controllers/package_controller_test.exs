defmodule HexWeb.PackageControllerTest do
  use HexWeb.ConnCase, async: true
  alias HexWeb.{Package, Release}

  setup do
    eric = create_user("eric", "eric@mail.com", "ericeric")
    decimal = Package.build(eric, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> HexWeb.Repo.insert!
    Package.build(eric, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"})) |> HexWeb.Repo.insert!
    Release.build(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> HexWeb.Repo.insert!
    Release.build(decimal, rel_meta(%{version: "0.0.2", app: "decimal"}), "") |> HexWeb.Repo.insert!
    :ok
  end

  test "index" do
    conn = get build_conn(), "/packages"
    assert conn.status == 200
    assert conn.resp_body =~ ~r/decimal.*0.0.2/
    assert conn.resp_body =~ ~r/postgrex/
  end

  test "index with letter" do
    conn = get build_conn(), "/packages?letter=D"
    assert conn.status == 200
    assert conn.resp_body =~ ~r/decimal/
    refute conn.resp_body =~ ~r/postgrex/

    conn = get build_conn(), "/packages?letter=P"
    assert conn.status == 200
    refute conn.resp_body =~ ~r/decimal/
    assert conn.resp_body =~ ~r/postgrex/
  end

  test "index with search query" do
    conn = get build_conn(), "/packages?search=dec"
    assert conn.status == 200
    assert conn.resp_body =~ ~r/decimal.*0.0.2/
    refute conn.resp_body =~ ~r/postgrex/
  end

  test "show package" do
    conn = get build_conn(), "/packages/decimal"
    assert response(conn, 200) =~ escape("{:decimal, \"~> 0.0.2\"}")
  end

  test "show package version" do
    conn = get build_conn(), "/packages/decimal/0.0.1"
    assert response(conn, 200) =~ escape("{:decimal, \"~> 0.0.1\"}")
  end

  defp escape(html) do
    {:safe, safe} = Phoenix.HTML.html_escape(html)
    safe
  end
end

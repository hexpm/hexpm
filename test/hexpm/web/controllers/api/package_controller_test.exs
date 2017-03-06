defmodule Hexpm.Web.API.PackageControllerTest do
  use Hexpm.ConnCase, async: true

  alias Hexpm.Repository.Package
  alias Hexpm.Repository.Release

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    decimal = Package.build(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."})) |> Hexpm.Repo.insert!
    postgrex = Package.build(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"})) |> Hexpm.Repo.insert!
    Release.build(decimal, rel_meta(%{version: "0.0.1", app: "decimal"}), "") |> Hexpm.Repo.insert!
    {:ok, decimal: decimal, postgrex: postgrex}
  end

  test "get package" do
    conn = get build_conn(), "api/packages/decimal"

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "decimal"

    release = List.first(body["releases"])
    assert release["url"] =~ "/api/packages/decimal/releases/0.0.1"
    assert release["version"] == "0.0.1"
  end

  test "get multiple packages" do
    conn = get build_conn(), "api/packages"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 2
    releases = List.first(body)["releases"]
    for release <- releases do
      assert length(Map.keys(release)) == 2
      assert Map.has_key?(release, "url")
      assert Map.has_key?(release, "version")
    end

    conn = get build_conn(), "api/packages?search=post"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 1

    conn = get build_conn(), "api/packages?search=name%3Apost*"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 1

    conn = get build_conn(), "api/packages?page=1"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 2

    conn = get build_conn(), "api/packages?page=2"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 0
  end

  test "fetch sort order", c do
    future = %{NaiveDateTime.utc_now | year: 2030}

    c.postgrex
    |> Ecto.Changeset.change(updated_at: future)
    |> Hexpm.Repo.update!

    c.decimal
    |> Ecto.Changeset.change(inserted_at: future)
    |> Hexpm.Repo.update!

    conn = get build_conn(), "api/packages?sort=updated_at"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert hd(body)["name"] == "postgrex"

    conn = get build_conn(), "api/packages?sort=inserted_at"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert hd(body)["name"] == "decimal"
  end
end

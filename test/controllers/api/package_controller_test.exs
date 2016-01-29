defmodule HexWeb.API.PackageControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true)
    {:ok, pkg}  = Package.create(user, pkg_meta(%{name: "decimal", description: "Arbitrary precision decimal arithmetic for Elixir."}))
    {:ok, _}    = Package.create(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"}))
    {:ok, _}    = Release.create(pkg, rel_meta(%{version: "0.0.1", app: "decimal"}), "")
    :ok
  end

  test "get package" do
    conn = get conn(), "api/packages/decimal"

    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert body["name"] == "decimal"

    release = List.first(body["releases"])
    assert release["url"] =~ "/api/packages/decimal/releases/0.0.1"
    assert release["version"] == "0.0.1"
  end

  test "get multiple packages" do
    conn = get conn(), "api/packages"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 2

    conn = get conn(), "api/packages?search=post"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 1

    conn = get conn(), "api/packages?page=1"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 2

    conn = get conn(), "api/packages?page=2"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert length(body) == 0
  end

  test "fetch sort order" do
    {year, month, day} = :erlang.date
    {:ok, future} = Ecto.Date.load({year + 1, month, day})

    Package.get("postgrex")
    |> Ecto.Changeset.change(updated_at: Ecto.DateTime.from_date(future))
    |> HexWeb.Repo.update!

    Package.get("decimal")
    |> Ecto.Changeset.change(inserted_at: Ecto.DateTime.from_date(future))
    |> HexWeb.Repo.update!

    conn = get conn(), "api/packages?sort=updated_at"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert hd(body)["name"] == "postgrex"

    conn = get conn(), "api/packages?sort=inserted_at"
    assert conn.status == 200
    body = Poison.decode!(conn.resp_body)
    assert hd(body)["name"] == "decimal"
  end
end

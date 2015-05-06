defmodule HexWeb.Feeds.RouterTest do
  use HexWebTest.Case
  import Plug.Test
  import Plug.Conn
  alias HexWeb.Router
  alias HexWeb.Package
  alias HexWeb.Release

  defp release_create(package, version, app, requirements, checksum, inserted_at) do
    {:ok, release} = Release.create(package, rel_meta(%{version: version, app: app, requirements: requirements}), checksum)
    %{release | inserted_at: inserted_at}
    |> HexWeb.Repo.update
  end

  setup do
    first_date  = Ecto.DateTime.from_erl({{2014, 5, 1}, {10, 11, 12}})
    second_date = Ecto.DateTime.from_erl({{2014, 5, 2}, {10, 11, 12}})
    last_date   = Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 12}})

    foo = HexWeb.Repo.insert(%Package{name: "foo", inserted_at: first_date, updated_at: first_date})
    bar = HexWeb.Repo.insert(%Package{name: "bar", inserted_at: second_date, updated_at: second_date})
    other = HexWeb.Repo.insert(%Package{name: "other", inserted_at: last_date, updated_at: last_date})

    release_create(foo, "0.0.1", "foo", [], "", last_date)
    release_create(foo, "0.0.2", "foo", [], "", last_date)
    release_create(foo, "0.1.0", "foo", [], "", last_date)
    release_create(bar, "0.0.1", "bar", [], "", last_date)
    release_create(bar, "0.0.2", "bar", [], "", last_date)
    release_create(other, "0.0.1", "other", [], "", last_date)
    :ok
  end

  test "new-packages.rss" do
    conn = conn(:get, "/feeds/new-packages.rss")
    conn = Router.call(conn, [])

    assert conn.status == 200
    assert Enum.count(conn.assigns[:packages]) == 3
    assert get_resp_header(conn, "content-type") == ["application/rss+xml"]
    assert String.starts_with?(conn.resp_body, "<?xml version=\"1.0\" encoding=\"utf-8\"?>")
  end
end

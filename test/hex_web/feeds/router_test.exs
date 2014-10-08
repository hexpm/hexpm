defmodule HexWeb.Feeds.RouterTest do
  use HexWebTest.Case
  import Plug.Test
  import Plug.Conn
  alias HexWeb.Router
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    first_date  = Ecto.DateTime.from_erl({{2014, 5, 1}, {10, 11, 12}})
    second_date = Ecto.DateTime.from_erl({{2014, 5, 2}, {10, 11, 12}})
    last_date   = Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 12}})

    foo = HexWeb.Repo.insert(%Package{name: "foo", meta: "{}", created_at: first_date, updated_at: first_date})
    bar = HexWeb.Repo.insert(%Package{name: "bar", meta: "{}", created_at: second_date, updated_at: second_date})
    other = HexWeb.Repo.insert(%Package{name: "other", meta: "{}", created_at: last_date, updated_at: last_date})

    {:ok, _} = Release.create(foo, "0.0.1", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 1}}))
    {:ok, _} = Release.create(foo, "0.0.2", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 2}}))
    {:ok, _} = Release.create(foo, "0.1.0", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 3}}))
    {:ok, _} = Release.create(bar, "0.0.1", "bar", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 4}}))
    {:ok, _} = Release.create(bar, "0.0.2", "bar", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 5}}))
    {:ok, _} = Release.create(other, "0.0.1", "other", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 6}}))
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

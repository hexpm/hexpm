defmodule Hexpm.SitemapControllerTest do
  use Hexpm.ConnCase, async: true

  alias Hexpm.Repository.Package

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    package = Package.build(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"})) |> Hexpm.Repo.insert!

    package
    |> Ecto.Changeset.change(updated_at: ~N[2014-04-17 14:00:00.000])
    |> Hexpm.Repo.update!
    :ok
  end

  test "sitemap" do
    conn = get build_conn(), "/sitemap.xml"
    assert response(conn, 200) == read_fixture("sitemap.xml")
  end
end

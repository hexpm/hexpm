defmodule HexWeb.SitemapControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Package

  setup do
    user = create_user("eric", "eric@mail.com", "ericeric")
    package = Package.build(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"})) |> HexWeb.Repo.insert!

    package
    |> Ecto.Changeset.change(updated_at: ~N[2014-04-17 14:00:00.000])
    |> HexWeb.Repo.update!
    :ok
  end

  test "sitemap" do
    conn = get build_conn(), "/sitemap.xml"

    path          = Path.join([__DIR__, "..", "fixtures"])
    expected_body = File.read!(Path.join(path, "sitemap.xml"))

    assert response(conn, 200) == expected_body
  end
end

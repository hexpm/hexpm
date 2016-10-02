defmodule HexWeb.SitemapControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Package
  alias HexWeb.User

  setup do
    user = User.build(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
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

defmodule HexWeb.SitemapControllerTest do
  use HexWeb.ConnCase

  alias HexWeb.Package
  alias HexWeb.User

  setup do
    user = User.create(%{username: "eric", email: "eric@mail.com", password: "eric"}, true) |> HexWeb.Repo.insert!
    {:ok, package} = Package.create(user, pkg_meta(%{name: "postgrex", description: "Postgrex is awesome"}))
    {:ok, date} = Ecto.DateTime.cast("2014-04-17T14:00:00Z")
    package
    |> Ecto.Changeset.change(updated_at: date)
    |> HexWeb.Repo.update!
    :ok
  end

  test "sitemap" do
    conn = get conn(), "/sitemap.xml"

    assert conn.status == 200

    path          = Path.join([__DIR__, "..", "fixtures"])
    expected_body = File.read!(Path.join(path, "sitemap.xml"))

    assert conn.resp_body == expected_body
  end
end

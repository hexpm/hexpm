defmodule HexWeb.PageControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Package
  alias HexWeb.Release

  defp create_user(username, email, password) do
    HexWeb.User.create(%{username: username, email: email, password: password}, true)
    |> HexWeb.Repo.insert!
  end

  defp release_create(package, version, app, requirements, checksum, inserted_at) do
    release = Release.create(package, rel_meta(%{version: version, app: app, requirements: requirements}), checksum)
              |> HexWeb.Repo.insert!
    Ecto.Changeset.change(release, inserted_at: inserted_at)
    |> HexWeb.Repo.update!
  end

  setup do
    first_date  = Ecto.DateTime.from_erl({{2014, 5, 1}, {10, 11, 12}})
    second_date = Ecto.DateTime.from_erl({{2014, 5, 2}, {10, 11, 12}})
    last_date   = Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 12}})

    eric = create_user("eric", "eric@example.com", "eric")

    foo = Package.create(eric, %{name: "foo", inserted_at: first_date, updated_at: first_date, meta: %{description: "foo", licenses: ["Apache"]}}) |> HexWeb.Repo.insert!
    bar = Package.create(eric, %{name: "bar", inserted_at: second_date, updated_at: second_date, meta: %{description: "bar", licenses: ["Apache"]}}) |> HexWeb.Repo.insert!
    other = Package.create(eric, %{name: "other", inserted_at: last_date, updated_at: last_date, meta: %{description: "other", licenses: ["Apache"]}}) |> HexWeb.Repo.insert!

    release_create(foo, "0.0.1", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 1}}))
    release_create(foo, "0.0.2", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 2}}))
    release_create(foo, "0.1.0", "foo", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 3}}))
    release_create(bar, "0.0.1", "bar", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 4}}))
    release_create(bar, "0.0.2", "bar", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 5}}))
    release_create(other, "0.0.1", "other", [], "", Ecto.DateTime.from_erl({{2014, 5, 3}, {10, 11, 6}}))
    :ok
  end

  test "index" do
    path     = Path.join([__DIR__, "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))

    HexWeb.Store.put_logs(nil, nil, "hex/2013-12-01-21-32-16-E568B2907131C0C0", logfile1)
    HexWeb.Store.put_logs(nil, nil, "hex/2013-12-01-21-32-19-E568B2907131C0C0", logfile2)
    HexWeb.StatsJob.run({2013, 12, 1}, [[nil, nil]])

    conn = get conn(), "/"

    assert conn.status == 200
    assert conn.assigns[:total]["all"] == 9
    assert conn.assigns[:total]["week"] == 0
    assert [{"foo", %Ecto.DateTime{}, %HexWeb.PackageMetadata{}, 7}, {"bar", %Ecto.DateTime{}, %HexWeb.PackageMetadata{}, 2}] = conn.assigns[:package_top]
    assert conn.assigns[:num_packages] == 3
    assert conn.assigns[:num_releases] == 6
    assert Enum.count(conn.assigns[:releases_new]) == 6
    assert Enum.count(conn.assigns[:package_new]) == 3
  end
end

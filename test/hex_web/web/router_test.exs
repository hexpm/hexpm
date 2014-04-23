defmodule HexWeb.Web.RouterTest do
  use HexWebTest.Case
  import Plug.Test
  alias HexWeb.Router
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release

  setup do
    { :ok, user } = User.create("eric", "eric@mail.com", "eric")
    { :ok, foo } = Package.create("foo", user, %{})
    { :ok, bar } = Package.create("bar", user, %{})
    { :ok, other } = Package.create("other", user, %{})

    { :ok, _ } = Release.create(foo, "0.0.1", [])
    { :ok, _ } = Release.create(foo, "0.0.2", [])
    { :ok, _ } = Release.create(foo, "0.1.0", [])
    { :ok, _ } = Release.create(bar, "0.0.1", [])
    { :ok, _ } = Release.create(bar, "0.0.2", [])
    { :ok, _ } = Release.create(other, "0.0.1", [])
    :ok
  end

  test "front page" do
    path = Path.join([__DIR__, "..", "..", "fixtures"])
    logfile1 = File.read!(Path.join(path, "s3_logs_1.txt"))
    logfile2 = File.read!(Path.join(path, "s3_logs_2.txt"))

    HexWeb.Config.store.put("logs/2013-11-01-21-32-16-E568B2907131C0C0", logfile1)
    HexWeb.Config.store.put("logs/2013-11-01-21-32-19-E568B2907131C0C0", logfile2)
    HexWeb.Stats.Job.run({ 2013, 11, 1 })

    conn = conn(:get, "/")
    conn = Router.call(conn, [])

    assert conn.status == 200
    assert conn.assigns[:total][:all] == 9
    assert conn.assigns[:total][:week] == 0
    assert conn.assigns[:package_top] == [{"foo", 7}, {"bar", 2}]
    assert conn.assigns[:num_packages] == 3
    assert conn.assigns[:num_releases] == 6
  end
end

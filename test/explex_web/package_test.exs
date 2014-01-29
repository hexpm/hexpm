defmodule ExplexWeb.PackageTest do
  use ExplexWebTest.Case

  alias ExplexWeb.User
  alias ExplexWeb.Package

  setup do
    User.create("eric", "eric")
    :ok
  end

  test "create package and get" do
    user = User.get("eric")
    assert { :ok, Package.Entity[] } = Package.create("ecto", user, [])
    assert Package.Entity[] = Package.get("ecto")
    assert nil?(Package.get("postgrex"))
  end
end

defmodule HexWeb.PackageTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package

  setup do
    {:ok, _} = User.create("eric", "eric@mail.com", "eric", true)
    :ok
  end

  test "create package and get" do
    user = User.get(username: "eric")
    user_id = user.id
    assert {:ok, %Package{}} = Package.create("ecto", user, %{})
    assert [%User{id: ^user_id}] = Package.get("ecto") |> Package.owners
    assert is_nil(Package.get("postgrex"))
  end

  test "update package" do
    user = User.get(username: "eric")
    assert {:ok, package} = Package.create("ecto", user, %{})

    Package.update(package, %{"contributors" => ["eric", "josé"]})
    package = Package.get("ecto")
    assert length(package.meta["contributors"]) == 2
  end

  test "validate valid meta" do
    meta = %{
      "contributors" => ["eric", "josé"],
      "licenses"     => ["apache", "BSD"],
      "links"        => %{"github" => "www", "docs" => "www"},
      "description"  => "so good"}

    user = User.get(username: "eric")
    assert {:ok, %Package{meta: ^meta}} = Package.create("ecto", user, meta)
    assert %Package{meta: ^meta} = Package.get("ecto")
  end

  test "ignore unknown meta fields" do
    meta = %{
      "contributors" => ["eric"],
      "foo"          => "bar"}

    user = User.get(username: "eric")
    assert {:ok, %Package{}} = Package.create("ecto", user, meta)
    assert %Package{meta: meta2} = Package.get("ecto")

    assert Map.size(meta2) == 1
    assert meta["contributors"] == meta2["contributors"]
  end

  # test "validate invalid meta" do
  #   meta = %{
  #     "contributors" => "eric",
  #     "licenses"     => 123,
  #     "links"        => ["url"],
  #     "description"  => ["so bad"]}

  #   user = User.get(username: "eric")
  #   assert {:error, errors} = Package.create("ecto", user, meta)
  #   assert Map.size(errors) == 1
  #   assert Map.size(errors[:meta]) == 4
  # end

  test "packages are unique" do
    user = User.get(username: "eric")
    assert {:ok, %Package{}} = Package.create("ecto", user, %{})
    assert {:error, _} = Package.create("ecto", user, %{})
  end

  test "reserved names" do
    user = User.get(username: "eric")
    assert {:error, %{name: ["is reserved"]}} = Package.create("elixir", user, %{})
  end
end

defmodule HexWeb.UserTest do
  use HexWebTest.Case

  alias HexWeb.User
  alias HexWeb.Package

  test "create user and auth" do
    assert {:ok, %User{}} = User.create(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
    assert User.get(username: "eric") |> User.auth?("hunter42")
  end

  test "create user and fail auth" do
    assert {:ok, %User{}} = User.create(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
    refute User.get(username: "josé") |> User.auth?("erics_pass")
    refute User.get(username: "eric") |> User.auth?("wrong_pass")
  end

  test "users name and email are unique" do
    assert {:ok, %User{}} = User.create(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
    assert {:error, _} = User.create(%{username: "eric", email: "mail@mail.com", password: "pass"}, true)
    assert {:error, _} = User.create(%{username: "name", email: "eric@mail.com", password: "pass"}, true)
  end

  test "update user" do
    assert {:ok, user} = User.create(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
    {:ok, _} = User.update(user, %{username: "eric", password: "new_pass"})

    user = User.get(username: "eric")
    assert User.auth?(user, "new_pass")
    refute User.auth?(user, "erics_pass")
  end

  test "get" do
    {:ok, user} = User.create(%{username: "joe", email: "joe@example.com", password: "joe"}, true)
    assert User.get(username: "joe").username == "joe"
    assert User.get(email: "joe@example.com").username == "joe"
    assert User.get(id: user.id).username == "joe"
  end

  test "packages" do
    {:ok, user} = User.create(%{username: "joe", email: "joe@example.com", password: "joe"}, true)
    {:ok, package} = Package.create(user, pkg_meta(%{name: "joe_package"}))
    assert User.packages(user) == [package]
  end
end

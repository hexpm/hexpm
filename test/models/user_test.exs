defmodule HexWeb.UserTest do
  use HexWeb.ModelCase

  alias HexWeb.User

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
end

defmodule HexWeb.UserTest do
  use HexWeb.ModelCase

  alias HexWeb.User

  test "create user and auth" do
    User.create(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
    |> HexWeb.Repo.insert!
    assert HexWeb.Repo.get_by!(User, username: "eric") |> User.password_auth?("hunter42")
  end

  test "create user and fail auth" do
    User.create(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
    |> HexWeb.Repo.insert!
    refute HexWeb.Repo.get_by(User, username: "josé") |> User.password_auth?("erics_pass")
    refute HexWeb.Repo.get_by(User, username: "eric") |> User.password_auth?("wrong_pass")
  end

  test "users name and email are unique" do
    User.create(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
    |> HexWeb.Repo.insert!
    assert {:error, _} = User.create(%{username: "eric", email: "mail@mail.com", password: "pass"}, true) |> HexWeb.Repo.insert
    assert {:error, _} = User.create(%{username: "name", email: "eric@mail.com", password: "pass"}, true) |> HexWeb.Repo.insert
  end

  test "update user" do
    user = User.create(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
           |> HexWeb.Repo.insert!
    User.update(user, %{username: "eric", password: "new_pass"})
    |> HexWeb.Repo.update!

    user = HexWeb.Repo.get_by!(User, username: "eric")
    assert User.password_auth?(user, "new_pass")
    refute User.password_auth?(user, "erics_pass")
  end
end

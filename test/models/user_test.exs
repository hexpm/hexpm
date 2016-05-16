defmodule HexWeb.UserTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.Auth
  alias HexWeb.User

  test "create user and auth" do
    User.build(%{username: "eric", email: "eric@mail.com", password: "hunter42"}, true)
    |> HexWeb.Repo.insert!
    assert {:ok, %User{username: "eric"}} = Auth.password_auth("eric", "hunter42")
  end

  test "create user and fail auth" do
    User.build(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
    |> HexWeb.Repo.insert!
    assert :error == Auth.password_auth("josé", "erics_pass")
    assert :error == Auth.password_auth("eric", "wrong_pass")
  end

  test "users name and email are unique" do
    User.build(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
    |> HexWeb.Repo.insert!
    assert {:error, _} = User.build(%{username: "eric", email: "mail@mail.com", password: "pass"}, true) |> HexWeb.Repo.insert
    assert {:error, _} = User.build(%{username: "name", email: "eric@mail.com", password: "pass"}, true) |> HexWeb.Repo.insert
  end

  test "update user" do
    user = User.build(%{username: "eric", email: "eric@mail.com", password: "erics_pass"}, true)
           |> HexWeb.Repo.insert!
    User.update(user, %{username: "eric", password: "new_pass"})
    |> HexWeb.Repo.update!

    assert {:ok, %User{username: "eric"}} = Auth.password_auth("eric", "new_pass")
    assert :error == Auth.password_auth("eric", "erics_pass")
  end
end

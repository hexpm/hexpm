defmodule HexWeb.UserTest do
  use HexWeb.ModelCase, async: true

  alias HexWeb.Auth
  alias HexWeb.User

  setup do
    %{user: create_user("eric", "eric@mail.com", "erics_pass")}
  end

  test "create user and auth" do
    assert {:ok, {%User{username: "eric"}, nil, _}} = Auth.password_auth("eric", "erics_pass")
  end

  test "create user and fail auth" do
    assert :error == Auth.password_auth("josé", "erics_pass")
    assert :error == Auth.password_auth("eric", "wrong_pass")
  end

  test "users name and email are unique" do
    assert {:error, _} = User.build(%{username: "eric", emails: [%{email: "mail@mail.com"}], password: "passpass"}, true) |> HexWeb.Repo.insert
    assert {:error, _} = User.build(%{username: "name", emails: [%{email: "eric@mail.com"}], password: "passpass"}, true) |> HexWeb.Repo.insert
  end

  test "update password", %{user: user} do
    User.update_password_no_check(user, %{username: "new_username", password: "new_pass"})
    |> HexWeb.Repo.update!

    assert {:ok, {%User{username: "eric"}, nil, _}} = Auth.password_auth("eric", "new_pass")
    assert :error == Auth.password_auth("eric", "erics_pass")
  end

  test "update profile", %{user: user} do
    User.update_profile(user, %{full_name: "Eric", username: "new_username", password: "new_pass"})
    |> HexWeb.Repo.update!

    assert {:ok, {%User{username: "eric", full_name: "Eric"}, nil, _}} = Auth.password_auth("eric", "erics_pass")
    assert :error == Auth.password_auth("eric", "new_pass")
  end
end

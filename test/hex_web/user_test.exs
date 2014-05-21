defmodule HexWeb.UserTest do
  use HexWebTest.Case

  alias HexWeb.User

  test "create user and auth" do
    assert { :ok, %User{} } = User.create("eric", "eric@mail.com", "hunter42")
    assert User.get("eric") |> User.auth?("hunter42")
  end

  test "create user and fail auth" do
    assert { :ok, %User{} } = User.create("eric", "eric@mail.com", "erics_pass")
    refute User.get("josé") |> User.auth?("erics_pass")
    refute User.get("eric") |> User.auth?("wrong_pass")
  end

  test "users name and email are unique" do
    assert { :ok, %User{} } = User.create("eric", "eric@mail.com", "erics_pass")
    assert { :error, _ } = User.create("eric", "mail@mail.com", "pass")
    assert { :error, _ } = User.create("name", "eric@mail.com", "pass")
  end

  test "update user" do
    assert { :ok, user } = User.create("eric", "eric@mail.com", "erics_pass")
    User.update(user, "other@mail.com", "new_pass")

    user = User.get("eric")
    assert user.email == "other@mail.com"
    assert User.auth?(user, "new_pass")
    refute User.auth?(user, "erics_pass")
  end
end

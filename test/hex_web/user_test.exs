defmodule HexWeb.UserTest do
  use HexWebTest.Case

  alias HexWeb.User

  test "create user and auth" do
    assert { :ok, User.Entity[] } = User.create("eric", "eric@mail.com", "hunter42")
    assert User.get("eric") |> User.auth?("hunter42")
  end

  test "create user and fail auth" do
    assert { :ok, User.Entity[] } = User.create("eric", "eric@mail.com", "erics_pass")
    refute User.get("josé") |> User.auth?("erics_pass")
    refute User.get("eric") |> User.auth?("wrong_pass")
  end

  test "users name and email are unique" do
    assert { :ok, User.Entity[] } = User.create("eric", "eric@mail.com", "erics_pass")
    assert { :error, _ } = User.create("eric", "mail@mail.com", "pass")
    assert { :error, _ } = User.create("name", "eric@mail.com", "pass")
  end
end

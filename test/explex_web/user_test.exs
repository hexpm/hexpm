defmodule ExplexWeb.UserTest do
  use ExplexWebTest.Case

  test "create user and auth" do
    assert User.Entity[] = User.create("eric", "hunter42")
    assert User.auth?("eric", "hunter42")
  end

  test "create user and fail auth" do
    assert User.Entity[] = User.create("eric", "erics_pass")
    refute User.auth?("josé", "erics_pass")
    refute User.auth?("eric", "wrong_pass")
  end
end

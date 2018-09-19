defmodule Hexpm.Accounts.UserTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{Auth, User}

  setup do
    user = insert(:user, password: Auth.gen_password("password"))
    %{user: user, password: "password"}
  end

  describe "build/2" do
    test "builds user" do
      changeset =
        User.build(%{
          username: "username",
          emails: [%{email: "mail@example.com"}],
          password: "password",
          full_name: "Jane Doe"
        })

      assert changeset.valid?
    end

    test "validates username" do
      changeset = User.build(%{username: "x"})
      assert errors_on(changeset)[:username] == "should be at least 3 character(s)"

      changeset = User.build(%{username: "{€%}"})
      assert errors_on(changeset)[:username] == "has invalid format"
    end

    test "validates password" do
      changeset = User.build(%{password: "x"})
      assert errors_on(changeset)[:password] == "should be at least 7 character(s)"
    end

    test "username and email are unique", %{user: user} do
      assert {:error, changeset} =
               User.build(
                 %{
                   username: user.username,
                   emails: [%{email: "some_other_email@example.com"}],
                   password: "password"
                 },
                 true
               )
               |> Hexpm.Repo.insert()

      assert errors_on(changeset)[:username] == "has already been taken"

      assert {:error, changeset} =
               User.build(
                 %{
                   username: "some_other_username",
                   emails: [%{email: hd(user.emails).email}],
                   password: "password"
                 },
                 true
               )
               |> Hexpm.Repo.insert()

      assert errors_on(changeset)[:emails][:email] == "already in use"
    end
  end

  describe "get/2" do
    test "gets the user by email", %{user: user} do
      email = User.email(user, :primary)

      fetched_user = User.get(email) |> Repo.one()
      assert user.id == fetched_user.id
    end

    test "gets the user by private email" do
      user =
        insert(
          :user,
          password: Auth.gen_password("password"),
          emails: [build(:email, public: false)]
        )

      email = User.email(user, :primary)

      fetched_user = User.get(email) |> Repo.one()
      assert user.id == fetched_user.id
    end

    test "gets the user by username", %{user: user} do
      fetched_user = User.get(user.username) |> Repo.one()
      assert user.id == fetched_user.id
    end
  end

  describe "public_get/2" do
    test "gets the user by public email", %{user: user} do
      email = User.email(user, :primary)

      fetched_user = User.public_get(email) |> Repo.one()
      assert user.id == fetched_user.id
    end

    test "doesn't get the user by private email" do
      user =
        insert(
          :user,
          password: Auth.gen_password("password"),
          emails: [build(:email, public: false)]
        )

      email = User.email(user, :primary)

      refute Repo.one(User.public_get(email))
    end
  end

  describe "update_password_no_check/2" do
    test "updates password", %{user: user} do
      User.update_password_no_check(user, %{
        username: "ignore_this",
        password: "new_password",
        password_confirmation: "new_password"
      })
      |> Hexpm.Repo.update!()

      assert {:ok, %{user: auth_user}} = Auth.password_auth(user.username, "new_password")

      assert auth_user.id == user.id
      assert :error == Auth.password_auth(user.username, "password")
    end

    test "validates", %{user: user} do
      changeset =
        User.update_password_no_check(user, %{
          username: "new_username",
          password: "short",
          password_confirmation: "short"
        })

      assert errors_on(changeset)[:password] == "should be at least 7 character(s)"

      changeset =
        User.update_password_no_check(user, %{
          username: "new_username",
          password: "new_password",
          password_confirmation: "new_password_wrong"
        })

      assert errors_on(changeset)[:password_confirmation] == "does not match password"
    end
  end

  describe "update_profile/2" do
    test "changes name", %{user: user} do
      changeset = User.update_profile(user, %{full_name: "Jane", username: "ignore_this"})
      assert changeset.valid?
      assert changeset.changes.full_name == "Jane"
      refute changeset.changes[:username]
    end

    test "does not change password", %{user: user, password: password} do
      User.update_profile(user, %{full_name: "Jane", password: "ignore_this"})
      |> Hexpm.Repo.update!()

      assert {:ok, _} = Auth.password_auth(user.username, password)
      assert :error == Auth.password_auth("new_username", "ignore_this")
    end
  end
end

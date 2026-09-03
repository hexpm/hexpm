defmodule Hexpm.Accounts.UserTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{Auth, BlockedEmailDomain, User, OptionalEmails}

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
          full_name: "Jane Doe",
          optional_emails: OptionalEmails.default_preferences()
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
      assert errors_on(changeset)[:password] == "should be at least 8 character(s)"
    end

    test "bounds the username in bytes" do
      changeset = User.build(%{username: String.duplicate("a", 255)})
      refute errors_on(changeset)[:username]

      changeset = User.build(%{username: String.duplicate("a", 256)})
      assert errors_on(changeset)[:username] == "should be at most 255 byte(s)"
    end

    test "bounds the full name in codepoints" do
      changeset = User.build(%{username: "username", full_name: codepoints_string(255)})
      refute errors_on(changeset)[:full_name]

      changeset = User.build(%{username: "username", full_name: codepoints_string(256)})
      assert errors_on(changeset)[:full_name] == "should be at most 255 character(s)"
    end

    test "bounds the email address in bytes" do
      at_cap = combining_string(250) <> "@b.co"
      assert byte_size(at_cap) == 255

      changeset =
        Hexpm.Accounts.Email.changeset(%Hexpm.Accounts.Email{}, :create, %{email: at_cap}, true)

      refute errors_on(changeset)[:email]

      over_cap = combining_string(252) <> "@b.co"

      changeset =
        Hexpm.Accounts.Email.changeset(%Hexpm.Accounts.Email{}, :create, %{email: over_cap}, true)

      assert errors_on(changeset)[:email] == "should be at most 255 byte(s)"
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

    test "rejects an email on a blocked domain or under it" do
      Repo.insert!(
        BlockedEmailDomain.changeset(%BlockedEmailDomain{}, %{domain: "Blocked.example"})
      )

      for email <- ["someone@blocked.example", "someone@mail.BLOCKED.example"] do
        assert {:error, changeset} =
                 User.build(
                   %{username: "blockeduser", emails: [%{email: email}], password: "password"},
                   true
                 )
                 |> Hexpm.Repo.insert()

        assert errors_on(changeset)[:emails][:email] == "uses a blocked domain"
      end

      assert {:ok, _user} =
               User.build(
                 %{
                   username: "blockeduser",
                   emails: [%{email: "someone@notblocked.example"}],
                   password: "password"
                 },
                 true
               )
               |> Hexpm.Repo.insert()
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

      assert errors_on(changeset)[:password] == "should be at least 8 character(s)"

      changeset =
        User.update_password_no_check(user, %{
          username: "new_username",
          password: "new_password",
          password_confirmation: "new_password_wrong"
        })

      assert errors_on(changeset)[:password_confirmation] == "does not match password"
    end
  end

  describe "verify_permissions/3" do
    test "refuses a package resource that names no package", %{user: user} do
      # The resource comes off the query string of /api/auth, so anything at all
      # can arrive here.
      for name <- ["decimal", "", "hexpm/decimal/1.0.0"] do
        assert User.verify_permissions(user, "package", name) == :error
      end
    end
  end

  describe "update_profile/2" do
    test "changes name", %{user: user} do
      changeset = User.update_profile(user, %{full_name: "Jane", username: "ignore_this"})
      assert changeset.valid?
      assert changeset.changes.full_name == "Jane"
      refute changeset.changes[:username]
    end

    test "bounds the full name in codepoints", %{user: user} do
      assert User.update_profile(user, %{full_name: codepoints_string(255)}).valid?

      changeset = User.update_profile(user, %{full_name: codepoints_string(256)})
      assert errors_on(changeset)[:full_name] == "should be at most 255 character(s)"
    end

    test "bounds the handles", %{user: user} do
      url = "https://example.com/" <> String.duplicate("a", 2028)
      handles = %{github: codepoints_string(255), url: url}
      assert User.update_profile(user, %{handles: handles}).valid?

      changeset = User.update_profile(user, %{handles: %{github: codepoints_string(256)}})
      assert errors_on(changeset).handles.github == "should be at most 255 character(s)"

      changeset = User.update_profile(user, %{handles: %{url: url <> "a"}})
      assert errors_on(changeset).handles.url == "should be at most 2048 byte(s)"
    end

    test "does not change password", %{user: user, password: password} do
      User.update_profile(user, %{full_name: "Jane", password: "ignore_this"})
      |> Hexpm.Repo.update!()

      assert {:ok, _} = Auth.password_auth(user.username, password)
      assert :error == Auth.password_auth("new_username", "ignore_this")
    end
  end
end

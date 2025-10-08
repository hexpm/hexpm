defmodule Hexpm.Accounts.UsersTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{Users, UserProviders}

  describe "add_from_oauth_with_provider/6" do
    test "creates user and provider atomically" do
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)
      email = Hexpm.Fake.sequence(:email)

      {:ok, user} =
        Users.add_from_oauth_with_provider(
          username,
          name,
          email,
          "github",
          "12345",
          audit: %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil},
          confirmed?: true
        )

      assert user.username == username
      assert user.full_name == name
      refute user.password

      assert [user_email] = user.emails
      assert user_email.email == email
      assert user_email.verified
      assert user_email.primary
      assert user_email.public

      user_provider = UserProviders.get_by_provider("github", "12345")
      assert user_provider
      assert user_provider.user_id == user.id
      assert user_provider.provider_email == email
    end

    test "creates all audit logs" do
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)
      email = Hexpm.Fake.sequence(:email)

      {:ok, user} =
        Users.add_from_oauth_with_provider(
          username,
          name,
          email,
          "github",
          "12345",
          audit: %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}
        )

      audit_logs = Hexpm.Accounts.AuditLogs.all_by(user)
      actions = Enum.map(audit_logs, & &1.action)

      assert "user.create" in actions
      assert "email.add" in actions
      assert "email.primary" in actions
      assert "email.public" in actions
      assert "user_provider.create" in actions
    end

    test "returns error when username is invalid" do
      name = Hexpm.Fake.sequence(:full_name)
      email = Hexpm.Fake.sequence(:email)

      {:error, changeset} =
        Users.add_from_oauth_with_provider(
          "ab",
          name,
          email,
          "github",
          "12345",
          audit: %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}
        )

      assert %{username: _} = errors_on(changeset)
    end

    test "returns error when username is taken" do
      username = Hexpm.Fake.sequence(:username)
      insert(:user, username: username)
      name = Hexpm.Fake.sequence(:full_name)
      email = Hexpm.Fake.sequence(:email)

      {:error, changeset} =
        Users.add_from_oauth_with_provider(
          username,
          name,
          email,
          "github",
          "12345",
          audit: %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}
        )

      assert %{username: _} = errors_on(changeset)
    end

    test "rolls back user creation when provider creation fails" do
      other_user = insert(:user)
      insert(:user_provider, user: other_user, provider: "github", provider_uid: "12345")
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)
      email = Hexpm.Fake.sequence(:email)

      {:error, _changeset} =
        Users.add_from_oauth_with_provider(
          username,
          name,
          email,
          "github",
          "12345",
          audit: %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}
        )

      refute Users.get(username)
    end

    test "does not create any audit logs on failure" do
      other_user = insert(:user)
      insert(:user_provider, user: other_user, provider: "github", provider_uid: "12345")
      username = Hexpm.Fake.sequence(:username)
      name = Hexpm.Fake.sequence(:full_name)
      email = Hexpm.Fake.sequence(:email)

      {:error, _changeset} =
        Users.add_from_oauth_with_provider(
          username,
          name,
          email,
          "github",
          "12345",
          audit: %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}
        )

      refute Users.get(username)
    end
  end

  describe "update_profile/3 when user is an organization" do
    test "updates full_name" do
      organization = insert(:organization, user: build(:user, full_name: "Old Full Name"))

      {:ok, updated_user} =
        Users.update_profile(
          organization.user,
          %{"full_name" => "New Full Name"},
          audit: audit_data(build(:user))
        )

      assert %{full_name: "New Full Name"} = updated_user
    end

    test "updates handles" do
      organization = insert(:organization, user: build(:user))

      {:ok, updated_user} =
        Users.update_profile(
          organization.user,
          %{
            "handles" => %{
              "twitter" => "twitter",
              "bluesky" => "bluesky",
              "github" => "github",
              "elixirforum" => "elixirforum",
              "freenode" => "freenode",
              "slack" => "slack"
            }
          },
          audit: audit_data(build(:user))
        )

      assert %{
               twitter: "twitter",
               bluesky: "bluesky",
               github: "github",
               elixirforum: "elixirforum",
               freenode: "freenode",
               slack: "slack"
             } = updated_user.handles
    end

    test "audits user.update action" do
      organization =
        insert(:organization, user: build(:user, username: "organization.user", emails: []))

      current_user = insert(:user)

      {:ok, _} =
        Users.update_profile(
          organization.user,
          %{},
          audit: audit_data(current_user)
        )

      assert [%{action: "user.update", params: %{"username" => "organization.user"}}] =
               Hexpm.Accounts.AuditLogs.all_by(current_user)
    end

    test "inserts public email if it doesn't exist yet" do
      organization = insert(:organization, user: build(:user, emails: []))
      current_user = insert(:user)
      email = Hexpm.Fake.sequence(:email)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => email},
          audit: audit_data(current_user)
        )

      assert user_email = Users.get_maybe_unverified_email(email)
      assert user_email.user_id == organization.user.id
      assert user_email.public
    end

    test "updates public email if it exists" do
      old_email = Hexpm.Fake.sequence(:email)
      new_email = Hexpm.Fake.sequence(:email)

      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: old_email, public: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => new_email},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email(old_email)
      assert email = Users.get_maybe_unverified_email(new_email)
      assert email.user_id == organization.user.id
      assert email.public
    end

    test "inserts gravatar email if it doesn't exist yet" do
      organization = insert(:organization, user: build(:user, emails: []))
      current_user = insert(:user)
      email = Hexpm.Fake.sequence(:email)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"gravatar_email" => email},
          audit: audit_data(current_user)
        )

      assert user_email = Users.get_maybe_unverified_email(email)
      assert user_email.user_id == organization.user.id
      assert user_email.gravatar
    end

    test "updates gravatar email if it exists" do
      old_email = Hexpm.Fake.sequence(:email)
      new_email = Hexpm.Fake.sequence(:email)

      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: old_email, gravatar: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"gravatar_email" => new_email},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email(old_email)
      assert email = Users.get_maybe_unverified_email(new_email)
      assert email.user_id == organization.user.id
      assert email.gravatar
    end

    test "inserts same public and gravatar email" do
      organization = insert(:organization, user: build(:user, emails: []))
      current_user = insert(:user)
      email = Hexpm.Fake.sequence(:email)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => email, "gravatar_email" => email},
          audit: audit_data(current_user)
        )

      assert user_email = Users.get_maybe_unverified_email(email)
      assert user_email.user_id == organization.user.id
      assert user_email.public
      assert user_email.gravatar
    end

    test "returns {:error, changeset} when public_email is invalid" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:error, _changeset} =
               Users.update_profile(
                 organization.user,
                 %{"public_email" => "public"},
                 audit: audit_data(build(:user))
               )
    end

    test "returns {:error, changeset} when gravatar_email is invalid" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:error, _changeset} =
               Users.update_profile(
                 organization.user,
                 %{"gravatar_email" => "gravatar"},
                 audit: audit_data(build(:user))
               )
    end

    test "removes public email when public_email is empty" do
      old_email = Hexpm.Fake.sequence(:email)

      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: old_email, public: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => ""},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email(old_email)
    end

    test "does nothing to emails when public_email is empty" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:ok, _updated_user} =
               Users.update_profile(
                 organization.user,
                 %{"public_email" => ""},
                 audit: audit_data(build(:user))
               )
    end

    test "removes gravatar email when gravatar_email is empty" do
      old_email = Hexpm.Fake.sequence(:email)

      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: old_email, gravatar: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"gravatar_email" => ""},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email(old_email)
    end

    test "does nothing to emails when gravatar_email is empty" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:ok, _updated_user} =
               Users.update_profile(
                 organization.user,
                 %{"gravatar_email" => ""},
                 audit: audit_data(build(:user))
               )
    end

    test "update two emails" do
      organization = insert(:organization, user: build(:user, emails: []))
      first_email = Hexpm.Fake.sequence(:email)
      second_email = Hexpm.Fake.sequence(:email)

      assert {:ok, _updated_user} =
               Users.update_profile(
                 organization.user,
                 %{
                   "public_email" => first_email,
                   "gravatar_email" => second_email
                 },
                 audit: audit_data(build(:user))
               )
    end
  end
end

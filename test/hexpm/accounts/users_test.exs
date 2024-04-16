defmodule Hexpm.Accounts.UsersTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Users

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

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => "public@example.com"},
          audit: audit_data(current_user)
        )

      assert email = Users.get_maybe_unverified_email("public@example.com")
      assert email.user_id == organization.user.id
      assert email.public
    end

    test "updates public email if it exists" do
      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: "old@example.com", public: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => "public@example.com"},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email("old@example.com")
      assert email = Users.get_maybe_unverified_email("public@example.com")
      assert email.user_id == organization.user.id
      assert email.public
    end

    test "inserts gravatar email if it doesn't exist yet" do
      organization = insert(:organization, user: build(:user, emails: []))
      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"gravatar_email" => "gravatar@example.com"},
          audit: audit_data(current_user)
        )

      assert email = Users.get_maybe_unverified_email("gravatar@example.com")
      assert email.user_id == organization.user.id
      assert email.gravatar
    end

    test "updates gravatar email if it exists" do
      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: "old@example.com", gravatar: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"gravatar_email" => "gravatar@example.com"},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email("old@example.com")
      assert email = Users.get_maybe_unverified_email("gravatar@example.com")
      assert email.user_id == organization.user.id
      assert email.gravatar
    end

    test "inserts same public and gravatar email" do
      organization = insert(:organization, user: build(:user, emails: []))
      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => "email@example.com", "gravatar_email" => "email@example.com"},
          audit: audit_data(current_user)
        )

      assert email = Users.get_maybe_unverified_email("email@example.com")
      assert email.user_id == organization.user.id
      assert email.public
      assert email.gravatar
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
      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: "old@example.com", public: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"public_email" => ""},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email("old@example.com")
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
      organization =
        insert(:organization,
          user: build(:user, emails: [build(:email, email: "old@example.com", gravatar: true)])
        )

      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"gravatar_email" => ""},
          audit: audit_data(current_user)
        )

      refute Users.get_maybe_unverified_email("old@example.com")
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

      assert {:ok, _updated_user} =
               Users.update_profile(
                 organization.user,
                 %{
                   "public_email" => "first@example.com",
                   "gravatar_email" => "second@example.com"
                 },
                 audit: audit_data(build(:user))
               )
    end
  end
end

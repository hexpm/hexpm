defmodule Hexpm.Accounts.UsersTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Users

  describe "update_profile/3 when user belongs to an organization" do
    test "updates full_name" do
      organization = insert(:organization, user: build(:user, full_name: "Old Full Name"))

      {:ok, updated_user} =
        Users.update_profile(
          organization.user,
          %{"full_name" => "New Full Name"},
          audit: {build(:user), "UA"}
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
          audit: {build(:user), "UA"}
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
          audit: {current_user, "UA"}
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
          audit: {current_user, "UA"}
        )

      email = Users.get_email("public@example.com")
      assert email.user_id == organization.user.id
      assert email.public == true

      current_user_id = current_user.id
      organization_id = organization.id

      assert [
               %{
                 action: "email.public",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               %{
                 action: "email.add",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               _user_update
             ] = Hexpm.Accounts.AuditLogs.all_by(current_user)
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
          audit: {current_user, "UA"}
        )

      email = Users.get_email("public@example.com")
      assert email.user_id == organization.user.id
      assert email.public == true

      current_user_id = current_user.id
      organization_id = organization.id

      assert [
               %{
                 action: "email.public",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               _user_update
             ] = Hexpm.Accounts.AuditLogs.all_by(current_user)
    end

    test "inserts gravatar email if it doesn't exist yet" do
      organization = insert(:organization, user: build(:user, emails: []))
      current_user = insert(:user)

      {:ok, _updated_user} =
        Users.update_profile(
          organization.user,
          %{"gravatar_email" => "gravatar@example.com"},
          audit: {current_user, "UA"}
        )

      email = Users.get_email("gravatar@example.com")
      assert email.user_id == organization.user.id
      assert email.gravatar == true

      current_user_id = current_user.id
      organization_id = organization.id

      assert [
               %{
                 action: "email.gravatar",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               %{
                 action: "email.add",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               _user_update
             ] = Hexpm.Accounts.AuditLogs.all_by(current_user)
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
          audit: {current_user, "UA"}
        )

      email = Users.get_email("gravatar@example.com")
      assert email.user_id == organization.user.id
      assert email.gravatar == true

      current_user_id = current_user.id
      organization_id = organization.id

      assert [
               %{
                 action: "email.gravatar",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               _user_update
             ] = Hexpm.Accounts.AuditLogs.all_by(current_user)
    end

    test "returns {:error, changeset} when public_email is invalid" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:error, _changeset} =
               Users.update_profile(
                 organization.user,
                 %{"public_email" => "public"},
                 audit: {build(:user), "UA"}
               )
    end

    test "returns {:error, changeset} when gravatar_email is invalid" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:error, _changeset} =
               Users.update_profile(
                 organization.user,
                 %{"gravatar_email" => "gravatar"},
                 audit: {build(:user), "UA"}
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
          audit: {current_user, "UA"}
        )

      assert Users.get_email("old@example.com") == nil

      current_user_id = current_user.id
      organization_id = organization.id

      assert [
               %{
                 action: "email.remove",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               _user_update
             ] = Hexpm.Accounts.AuditLogs.all_by(current_user)
    end

    test "does nothing to emails when public_email is empty" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:ok, _updated_user} =
               Users.update_profile(
                 organization.user,
                 %{"public_email" => ""},
                 audit: {build(:user), "UA"}
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
          audit: {current_user, "UA"}
        )

      assert Users.get_email("old@example.com") == nil

      current_user_id = current_user.id
      organization_id = organization.id

      assert [
               %{
                 action: "email.remove",
                 user_id: ^current_user_id,
                 organization_id: ^organization_id
               },
               _user_update
             ] = Hexpm.Accounts.AuditLogs.all_by(current_user)
    end

    test "does nothing to emails when gravatar_email is empty" do
      organization = insert(:organization, user: build(:user, emails: []))

      assert {:ok, _updated_user} =
               Users.update_profile(
                 organization.user,
                 %{"gravatar_email" => ""},
                 audit: {build(:user), "UA"}
               )
    end
  end
end

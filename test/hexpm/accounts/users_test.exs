defmodule Hexpm.Accounts.UsersTest do
  use Hexpm.DataCase, async: true

  import Swoosh.TestAssertions

  alias Hexpm.Accounts.{AuditLog, OptionalEmails, User, Users, UserProviders}

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
      assert user.optional_emails == OptionalEmails.default_preferences()

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

  test "new users default to optional email preferences" do
    username = Hexpm.Fake.sequence(:username)
    email = Hexpm.Fake.sequence(:email)

    params = %{
      "username" => username,
      "emails" => [%{"email" => email}]
    }

    audit = %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}

    {:ok, user} = Users.add(params, audit: audit)

    assert user.optional_emails == OptionalEmails.default_preferences()
  end

  test "rejects invalid optional email values" do
    user = insert(:user)

    changeset =
      User.optional_emails_changeset(user, %{"organization_invite" => "yes"})

    assert %{optional_emails: _} = errors_on(changeset)
  end

  test "rejects unknown optional email keys" do
    user = insert(:user)

    changeset =
      User.optional_emails_changeset(user, %{"unknown_pref" => true})

    assert %{optional_emails: _} = errors_on(changeset)
  end

  describe "add/2 with reserved username" do
    test "rejects a username in reserved_usernames" do
      Repo.insert!(%Hexpm.Accounts.ReservedUsername{name: "graveyard"})

      params = %{
        "username" => "graveyard",
        "emails" => [%{"email" => Hexpm.Fake.sequence(:email)}]
      }

      audit = %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}

      assert {:error, changeset} = Users.add(params, audit: audit)
      assert %{username: "has already been taken"} = errors_on(changeset)
    end

    test "comparison is case-insensitive" do
      Repo.insert!(%Hexpm.Accounts.ReservedUsername{name: "GraveYard"})

      params = %{
        "username" => "graveyard",
        "emails" => [%{"email" => Hexpm.Fake.sequence(:email)}]
      }

      audit = %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}

      assert {:error, changeset} = Users.add(params, audit: audit)
      assert %{username: "has already been taken"} = errors_on(changeset)
    end
  end

  describe "delete/2" do
    test "deletes the user, preserves packages/releases/audit logs, reserves the username" do
      user = insert(:user)
      other_owner = insert(:user)

      sole_package = insert(:package, package_owners: [build(:package_owner, user: user)])

      co_package =
        insert(:package,
          package_owners: [
            build(:package_owner, user: user),
            build(:package_owner, user: other_owner)
          ]
        )

      release = insert(:release, package: sole_package, publisher: user)
      key = insert(:key, user: user)
      session = insert(:session, user_id: user.id)

      organization = insert(:organization)
      org_user = insert(:organization_user, user: user, organization: organization)

      old_log =
        insert(:audit_log, user: user, action: "user.update", user_data: %{"id" => user.id})

      email_ids = Enum.map(user.emails, & &1.id)
      username = user.username
      primary_email = User.email(user, :primary)

      assert :ok = Users.delete(user, audit: audit_data(user))

      # user row gone
      refute Repo.get(User, user.id)

      # packages and releases preserved, publisher nulled
      assert Repo.get(Hexpm.Repository.Package, sole_package.id)
      assert Repo.get(Hexpm.Repository.Package, co_package.id)
      assert Repo.get(Hexpm.Repository.Release, release.id).publisher_id == nil

      # ownership rows gone; the co-owned package keeps its other owner
      sole_reloaded = Repo.get(Hexpm.Repository.Package, sole_package.id)
      co_reloaded = Repo.get(Hexpm.Repository.Package, co_package.id)
      assert Repo.all(Ecto.assoc(sole_reloaded, :package_owners)) == []
      assert [%{user_id: other_id}] = Repo.all(Ecto.assoc(co_reloaded, :package_owners))
      assert other_id == other_owner.id

      # credentials and memberships gone
      refute Repo.get(Hexpm.Accounts.Key, key.id)
      refute Repo.get(Hexpm.UserSession, session.id)
      refute Repo.get(Hexpm.Accounts.OrganizationUser, org_user.id)
      for email_id <- email_ids, do: refute(Repo.get(Hexpm.Accounts.Email, email_id))

      # audit logs preserved with snapshot; a user.delete log was written
      assert Repo.get(AuditLog, old_log.id).user_id == nil

      delete_log = Repo.get_by(AuditLog, action: "user.delete")
      assert delete_log
      assert delete_log.user_id == nil
      assert delete_log.user_data["username"] == username
      assert delete_log.params["username"] == username

      # username reserved
      assert Repo.exists?(Hexpm.Accounts.ReservedUsername.by_name(username))

      # notice sent to the former primary email
      assert_email_sent(fn email ->
        email.subject == "Hex.pm - Your account has been deleted" and
          Enum.any?(email.to, fn {_name, address} -> address == primary_email end)
      end)
    end

    test "deletes a user without a primary email and sends no email" do
      user = insert(:user, emails: [])

      assert :ok = Users.delete(user, audit: audit_data(user))

      refute Repo.get(User, user.id)
      refute_email_sent()
    end

    test "re-registering a deleted username fails" do
      user = insert(:user)
      username = user.username
      assert :ok = Users.delete(user, audit: audit_data(user))

      params = %{
        "username" => username,
        "emails" => [%{"email" => Hexpm.Fake.sequence(:email)}]
      }

      audit = %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}
      assert {:error, changeset} = Users.add(params, audit: audit)
      assert %{username: "has already been taken"} = errors_on(changeset)
    end
  end

  describe "delete_eligibility/1" do
    test "ok with no warnings for a plain user" do
      user = insert(:user)
      assert {:ok, %{sole_owned_packages: []}} = Users.delete_eligibility(user)
    end

    test "warns about packages where the user is the sole owner" do
      user = insert(:user)
      other = insert(:user)

      sole = insert(:package, package_owners: [build(:package_owner, user: user)])

      _co =
        insert(:package,
          package_owners: [
            build(:package_owner, user: user),
            build(:package_owner, user: other)
          ]
        )

      assert {:ok, %{sole_owned_packages: [package]}} = Users.delete_eligibility(user)
      assert package.id == sole.id
    end

    test "blocks the last member of an organization" do
      user = insert(:user)
      organization = insert(:organization)
      insert(:organization_user, user: user, organization: organization, role: "admin")

      assert {:error, {:organizations, [blocked]}} = Users.delete_eligibility(user)
      assert blocked.id == organization.id
    end

    test "blocks the last admin even when other members exist" do
      user = insert(:user)
      other = insert(:user)
      organization = insert(:organization)
      insert(:organization_user, user: user, organization: organization, role: "admin")
      insert(:organization_user, user: other, organization: organization, role: "write")

      assert {:error, {:organizations, [blocked]}} = Users.delete_eligibility(user)
      assert blocked.id == organization.id
    end

    test "allows a non-last admin" do
      user = insert(:user)
      other = insert(:user)
      organization = insert(:organization)
      insert(:organization_user, user: user, organization: organization, role: "admin")
      insert(:organization_user, user: other, organization: organization, role: "admin")

      assert {:ok, _} = Users.delete_eligibility(user)
    end

    test "blocks organization service accounts" do
      organization = insert(:organization)
      assert {:error, :organization_account} = Users.delete_eligibility(organization.user)
    end

    test "does not warn about private repository packages" do
      user = insert(:user)
      repository = insert(:repository)

      insert(:package,
        repository_id: repository.id,
        package_owners: [build(:package_owner, user: user)]
      )

      assert {:ok, %{sole_owned_packages: []}} = Users.delete_eligibility(user)
    end
  end

  describe "delete_request/2 and delete_confirm/3" do
    test "creates a request, emails the confirmation link, and confirm deletes the account" do
      user = insert(:user)
      username = user.username

      assert :ok = Users.delete_request(user, audit: audit_data(user))

      request = Repo.get_by!(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)
      user = Repo.preload(user, :emails)
      assert_email_sent(Hexpm.Emails.account_deletion_request(user, request))

      request_log = Repo.get_by(Hexpm.Accounts.AuditLog, action: "user.delete.request")
      assert request_log.user_id == user.id

      assert :ok = Users.delete_confirm(user, request.key, audit: audit_data(user))
      refute Repo.get(User, user.id)
      assert Repo.exists?(Hexpm.Accounts.ReservedUsername.by_name(username))
      refute Repo.get(Hexpm.Accounts.AccountDeletionRequest, request.id)
    end

    test "a new request replaces the previous one" do
      user = insert(:user)

      assert :ok = Users.delete_request(user, audit: audit_data(user))
      first = Repo.get_by!(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)

      assert :ok = Users.delete_request(user, audit: audit_data(user))
      second = Repo.get_by!(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)

      assert first.id != second.id

      assert {:error, :invalid_request} =
               Users.delete_confirm(user, first.key, audit: audit_data(user))

      assert Repo.get(User, user.id)
    end

    test "confirm rejects a wrong, expired, or foreign key" do
      user = insert(:user)
      attacker = insert(:user)

      assert :ok = Users.delete_request(user, audit: audit_data(user))
      request = Repo.get_by!(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)

      # wrong key
      assert {:error, :invalid_request} =
               Users.delete_confirm(user, "deadbeef", audit: audit_data(user))

      # foreign key: attacker's own request used against user's account
      assert :ok = Users.delete_request(attacker, audit: audit_data(attacker))
      attacker_request = Repo.get_by!(Hexpm.Accounts.AccountDeletionRequest, user_id: attacker.id)

      assert {:error, :invalid_request} =
               Users.delete_confirm(user, attacker_request.key, audit: audit_data(user))

      # expired key
      Repo.update_all(Hexpm.Accounts.AccountDeletionRequest,
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :day)]
      )

      assert {:error, :invalid_request} =
               Users.delete_confirm(user, request.key, audit: audit_data(user))

      assert Repo.get(User, user.id)
    end

    test "request is blocked for users failing eligibility" do
      user = insert(:user)
      organization = insert(:organization)
      insert(:organization_user, user: user, organization: organization, role: "admin")

      assert {:error, {:organizations, _}} = Users.delete_request(user, audit: audit_data(user))
    end

    test "request is rejected for users without a primary email" do
      user = insert(:user, emails: [])

      assert {:error, :no_primary_email} = Users.delete_request(user, audit: audit_data(user))
      refute Repo.get_by(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)
    end

    test "changing the password deletes pending requests" do
      user = insert(:user)
      assert :ok = Users.delete_request(user, audit: audit_data(user))

      {:ok, _} =
        Users.update_password(
          user,
          %{
            "password_current" => "password",
            "password" => "new_password_123",
            "password_confirmation" => "new_password_123"
          },
          audit: audit_data(user)
        )

      refute Repo.get_by(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)
    end

    test "changing the primary email deletes the pending request" do
      user = insert(:user)
      assert :ok = Users.delete_request(user, audit: audit_data(user))
      request = Repo.get_by!(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)

      {:ok, user} = Users.add_email(user, %{email: "new@example.com"}, audit: audit_data(user))
      new_email = Enum.find(user.emails, &(&1.email == "new@example.com"))
      Repo.update!(Ecto.Changeset.change(new_email, verified: true))
      user = Users.get_by_id(user.id, [:emails])
      :ok = Users.primary_email(user, %{"email" => "new@example.com"}, audit: audit_data(user))

      refute Repo.get_by(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)

      user = Users.get_by_id(user.id, [:emails])

      assert {:error, :invalid_request} =
               Users.delete_confirm(user, request.key, audit: audit_data(user))
    end

    test "password reset deletes pending requests" do
      user = insert(:user)
      assert :ok = Users.delete_request(user, audit: audit_data(user))

      :ok = Users.password_reset_init(user.username, audit: audit_data(user))
      user = Users.get_by_id(user.id, [:emails, :password_resets])
      [reset] = user.password_resets

      :ok =
        Users.password_reset_finish(
          user.username,
          reset.key,
          %{
            "username" => user.username,
            "password" => "new_password_123",
            "password_confirmation" => "new_password_123"
          },
          false,
          audit: audit_data(user)
        )

      refute Repo.get_by(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)
    end

    test "confirm is blocked when eligibility changed after the request" do
      user = insert(:user)
      assert :ok = Users.delete_request(user, audit: audit_data(user))
      request = Repo.get_by!(Hexpm.Accounts.AccountDeletionRequest, user_id: user.id)

      organization = insert(:organization)
      insert(:organization_user, user: user, organization: organization, role: "admin")

      assert {:error, {:organizations, _}} =
               Users.delete_confirm(user, request.key, audit: audit_data(user))

      assert Repo.get(User, user.id)
    end

    test "confirm rejects a nil key" do
      user = insert(:user)
      assert :ok = Users.delete_request(user, audit: audit_data(user))

      assert {:error, :invalid_request} = Users.delete_confirm(user, nil, audit: audit_data(user))
      assert Repo.get(User, user.id)
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
              "slack" => "slack",
              "url" => "https://example.com"
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
               slack: "slack",
               url: "https://example.com"
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

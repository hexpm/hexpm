defmodule Hexpm.AdminTasksTest do
  use Hexpm.DataCase, async: true
  use Oban.Testing, repo: Hexpm.RepoBase
  import Swoosh.TestAssertions

  alias Hexpm.AdminTasks
  alias Hexpm.Accounts.{Organization, OrganizationUser, User}
  alias Hexpm.Emails.{OutboxEntry, OutboxWorker}
  alias Hexpm.Repository.{Package, Release}

  describe "change_password/3" do
    test "changes password by username" do
      user = insert(:user, username: "testuser")

      assert :ok = AdminTasks.change_password(:username, "testuser", "new_password")

      updated_user = Repo.get!(User, user.id)
      assert Bcrypt.verify_pass("new_password", updated_user.password)
    end

    test "changes password by email" do
      email = Fake.sequence(:email)
      user = insert(:user, emails: [build(:email, email: email)])

      assert :ok = AdminTasks.change_password(:email, email, "new_password")

      updated_user = Repo.get!(User, user.id)
      assert Bcrypt.verify_pass("new_password", updated_user.password)
    end

    test "returns error for nonexistent username" do
      assert {:error, :user_not_found} =
               AdminTasks.change_password(:username, "nonexistent", "password")
    end

    test "returns error for nonexistent email" do
      assert {:error, :user_not_found} =
               AdminTasks.change_password(:email, "nonexistent@example.com", "password")
    end
  end

  describe "reset_tfa/1" do
    test "disables 2FA for user with 2FA enabled" do
      user = insert(:user_with_tfa)

      assert User.tfa_enabled?(user)
      assert :ok = AdminTasks.reset_tfa(user.username)

      updated_user = Repo.get!(User, user.id)
      refute User.tfa_enabled?(updated_user)
    end

    test "returns error when 2FA is not enabled" do
      user = insert(:user)

      assert {:error, :tfa_not_enabled} = AdminTasks.reset_tfa(user.username)
    end

    test "returns error for nonexistent user" do
      assert {:error, :user_not_found} = AdminTasks.reset_tfa("nonexistent")
    end

    test "finds user by email" do
      email = Fake.sequence(:email)
      user = insert(:user_with_tfa, emails: [build(:email, email: email)])

      assert :ok = AdminTasks.reset_tfa(email)

      updated_user = Repo.get!(User, user.id)
      refute User.tfa_enabled?(updated_user)
    end
  end

  describe "remove_user/1" do
    test "removes user" do
      user = insert(:user)
      user_id = user.id

      assert :ok = AdminTasks.remove_user(user.username)

      refute Repo.get(User, user_id)
    end

    test "returns error for nonexistent user" do
      assert {:error, :user_not_found} = AdminTasks.remove_user("nonexistent")
    end

    test "reserves the username and writes an audit log" do
      user = insert(:user)
      username = user.username

      assert :ok = AdminTasks.remove_user(user.username)

      assert Repo.exists?(Hexpm.Accounts.ReservedUsername.by_name(username))

      delete_log = Repo.get_by(Hexpm.Accounts.AuditLog, action: "user.delete")
      assert delete_log
      assert delete_log.params["username"] == username
      assert delete_log.user_agent == "ADMIN"
    end

    test "does not send a notification email when removing a user" do
      user = insert(:user)

      assert :ok = AdminTasks.remove_user(user.username)

      refute_email_sent()
    end

    test "removes user with associated records" do
      user = insert(:user)
      user_id = user.id
      email_ids = Enum.map(user.emails, & &1.id)

      key = insert(:key, user: user)
      package = insert(:package)
      package_owner = insert(:package_owner, package: package, user: user)
      session = insert(:session, user_id: user.id)
      oauth_client = insert(:oauth_client)
      oauth_token = insert(:oauth_token, user: user, client_id: oauth_client.client_id)

      audit_log =
        insert(:audit_log,
          user: user,
          action: "test.action",
          user_data: %{"id" => user.id, "username" => user.username}
        )

      audit_log_with_key =
        insert(:audit_log,
          user: user,
          key: key,
          action: "test.key_action",
          user_data: %{"id" => user.id, "username" => user.username},
          key_data: %{"id" => key.id, "name" => key.name}
        )

      organization = insert(:organization)
      org_user = insert(:organization_user, user: user, organization: organization)

      password_reset =
        Repo.insert!(%Hexpm.Accounts.PasswordReset{
          key: "test_key",
          primary_email: "test@example.com",
          user_id: user.id
        })

      release = insert(:release, package: package, publisher: user)

      assert :ok = AdminTasks.remove_user(user.username)

      refute Repo.get(User, user_id)

      # CASCADE deletes
      for email_id <- email_ids do
        refute Repo.get(Hexpm.Accounts.Email, email_id)
      end

      refute Repo.get(Hexpm.Accounts.Key, key.id)
      refute Repo.get(Hexpm.Repository.PackageOwner, package_owner.id)
      refute Repo.get(Hexpm.UserSession, session.id)
      refute Repo.get(Hexpm.OAuth.Token, oauth_token.id)
      refute Repo.get(Hexpm.Accounts.OrganizationUser, org_user.id)
      refute Repo.get(Hexpm.Accounts.PasswordReset, password_reset.id)

      # SET NULL preserves records, user_data and key_data survive deletion
      audit_log_reloaded = Repo.get(Hexpm.Accounts.AuditLog, audit_log.id)
      assert audit_log_reloaded.user_id == nil
      assert audit_log_reloaded.user_data["username"] == user.username

      audit_log_with_key_reloaded = Repo.get(Hexpm.Accounts.AuditLog, audit_log_with_key.id)
      assert audit_log_with_key_reloaded.user_id == nil
      assert audit_log_with_key_reloaded.key_id == nil
      assert audit_log_with_key_reloaded.user_data["username"] == user.username
      assert audit_log_with_key_reloaded.key_data["name"] == key.name
      assert Repo.get(Release, release.id).publisher_id == nil
    end
  end

  describe "remove_user/2 with delete_packages" do
    test "deletes sole-owned packages" do
      user = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: user)
      package_id = package.id

      assert :ok = AdminTasks.remove_user(user.username, delete_packages: true)

      refute Repo.get(User, user.id)
      refute Repo.get(Package, package_id)
    end

    test "preserves packages with multiple owners" do
      user = insert(:user)
      other_user = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: user)
      insert(:package_owner, package: package, user: other_user)
      package_id = package.id

      assert :ok = AdminTasks.remove_user(user.username, delete_packages: true)

      refute Repo.get(User, user.id)
      assert Repo.get(Package, package_id)
    end

    test "without option leaves packages intact" do
      user = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: user)
      insert(:release, package: package, publisher: user)
      package_id = package.id

      assert :ok = AdminTasks.remove_user(user.username)

      refute Repo.get(User, user.id)
      assert Repo.get(Package, package_id)
    end
  end

  describe "remove_user/2 with reason" do
    test "emails the user why the account was removed" do
      user = insert(:user)
      address = User.email(user, :primary)

      assert :ok =
               AdminTasks.remove_user(user.username,
                 reason: "The account only published packages advertising an unrelated site."
               )

      assert_email_sent(fn email ->
        assert email.to == [{user.username, address}]
        assert email.subject == "Hex.pm - Your account has been removed"
        assert email.text_body =~ user.username
        assert email.text_body =~ "advertising an unrelated site"
        assert email.html_body =~ "advertising an unrelated site"
      end)
    end

    test "escapes the reason in the html email" do
      user = insert(:user)

      assert :ok = AdminTasks.remove_user(user.username, reason: "<script>alert(1)</script>")

      assert_email_sent(fn email ->
        refute email.html_body =~ "<script>"
        assert email.html_body =~ "&lt;script&gt;"
      end)
    end

    test "sends one email when sole-owned packages are deleted too" do
      user = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: user)
      package_id = package.id

      assert :ok =
               AdminTasks.remove_user(user.username,
                 delete_packages: true,
                 reason: "Bulk spam publishing."
               )

      refute Repo.get(Package, package_id)

      assert_email_sent(fn email ->
        assert email.subject == "Hex.pm - Your account has been removed"
      end)

      refute_email_sent()
    end

    test "sends the canned text for a reason id" do
      user = insert(:user)

      assert :ok = AdminTasks.remove_user(user.username, reason: :spam_account)

      assert_email_sent(fn email ->
        assert email.text_body =~ AdminTasks.reasons(:user)[:spam_account]
      end)
    end

    test "rejects an unknown reason without deleting the user" do
      user = insert(:user)
      user_id = user.id

      assert {:error, {:unknown_reason, :empty}} =
               AdminTasks.remove_user(user.username, reason: :empty)

      assert Repo.get(User, user_id)
      refute_email_sent()
    end

    test "says the packages went too when delete_packages deleted them" do
      user = insert(:user)
      package = insert(:package)
      insert(:package_owner, package: package, user: user)

      assert :ok =
               AdminTasks.remove_user(user.username,
                 delete_packages: true,
                 reason: :spam_account
               )

      assert_email_sent(fn email ->
        assert email.text_body =~ "along with the packages it was the only owner of"
      end)
    end

    test "does not mention packages when none were deleted" do
      user = insert(:user)

      assert :ok = AdminTasks.remove_user(user.username, reason: :spam_account)

      assert_email_sent(fn email ->
        refute email.text_body =~ "along with the packages"
        assert email.text_body =~ "The username has been retired"
      end)
    end

    # An unverified address was never proved to belong to the account, and a
    # removal notice accuses whoever receives it.
    test "does not accuse an address the account never verified" do
      user = insert(:user, emails: [build(:email, verified: false)])

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :ok = AdminTasks.remove_user(user.username, reason: :malware)
        end)

      refute Repo.get(User, user.id)
      assert log =~ "found no address for user #{user.username}"
      refute_email_sent()
    end
  end

  describe "the removal emails themselves" do
    # The appeal line is the only actionable thing in these emails and nothing
    # asserted it, so replacing Common.questions_notice/1 or reason_heading/0
    # with a literal left the whole suite green.
    test "each one carries the reason, its heading, and how to appeal" do
      user = build(:user)

      emails = [
        Hexpm.Emails.package_removed([user], "pkg", "Because of a thing."),
        Hexpm.Emails.release_removed([user], "pkg", "1.0.0", 2, "Because of a thing."),
        Hexpm.Emails.account_removed(user, false, "Because of a thing.")
      ]

      for email <- emails do
        assert email.text_body =~ "Reason:"
        assert email.text_body =~ "Because of a thing."
        assert email.text_body =~ "contact support at support@hex.pm"
        assert email.text_body =~ "/policies/termsofservice"

        assert email.html_body =~ "Reason:"
        assert email.html_body =~ "Because of a thing."
        assert email.html_body =~ "mailto:support@hex.pm"
        assert email.html_body =~ "/policies/termsofservice"
      end
    end

    test "a multi-paragraph reason becomes separate paragraphs in the html" do
      email = Hexpm.Emails.account_removed(build(:user), false, "First one.\n\nSecond one.")

      assert email.text_body =~ "First one."
      assert email.text_body =~ "Second one."
      assert email.html_body =~ ~r/First one\..*<\/p>.*<p[^>]*>\s*Second one\./s
    end
  end

  describe "reasons/1" do
    test "lists only the reasons that fit the scope" do
      assert :name_squatting in Keyword.keys(AdminTasks.reasons(:package))
      refute :name_squatting in Keyword.keys(AdminTasks.reasons(:release))
      refute :name_squatting in Keyword.keys(AdminTasks.reasons(:user))

      assert :spam_account in Keyword.keys(AdminTasks.reasons(:user))
      refute :spam_account in Keyword.keys(AdminTasks.reasons(:package))
    end

    # A lint against future typos, not a check that the wording is any good.
    test "no reason text is a stub" do
      for scope <- [:package, :release, :user], {id, text} <- AdminTasks.reasons(scope) do
        assert String.length(text) > 20, "#{id} is too short to explain anything"
        assert String.ends_with?(text, "."), "#{id} does not end in a sentence"
      end
    end

    test "no reason text names the subject the email already named" do
      for scope <- [:package, :release, :user], {id, text} <- AdminTasks.reasons(scope) do
        refute text =~ ~r/\bthis account\b/i, "#{id} names the subject"
        refute text =~ ~r/\byour (account|package)\b/i, "#{id} names the subject"
      end
    end

    test "raises a readable error on an unknown scope" do
      assert_raise ArgumentError, ~r/unknown scope :packages/, fn ->
        AdminTasks.reasons(:packages)
      end
    end
  end

  describe "rename_user/2" do
    test "renames user" do
      user = insert(:user, username: "oldname")

      assert :ok = AdminTasks.rename_user("oldname", "newname")

      updated_user = Repo.get!(User, user.id)
      assert updated_user.username == "newname"
    end

    test "returns error for nonexistent user" do
      assert {:error, :user_not_found} = AdminTasks.rename_user("nonexistent", "newname")
    end
  end

  describe "remove_organization_member/2" do
    test "removes an organization member and writes an admin audit log" do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: insert(:user))
      user = insert(:user)
      organization_user = insert(:organization_user, organization: organization, user: user)

      assert :ok = AdminTasks.remove_organization_member(organization.name, user.username)

      refute Repo.get(OrganizationUser, organization_user.id)

      audit_log = Repo.get_by(Hexpm.Accounts.AuditLog, action: "organization.member.remove")
      assert audit_log.user_agent == "ADMIN"
      assert audit_log.params["organization"]["name"] == organization.name
      assert audit_log.params["user"]["username"] == user.username
    end

    test "finds a member by email" do
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: insert(:user))
      email = Fake.sequence(:email)
      user = insert(:user, emails: [build(:email, email: email)])
      organization_user = insert(:organization_user, organization: organization, user: user)

      assert :ok = AdminTasks.remove_organization_member(organization.name, email)

      refute Repo.get(OrganizationUser, organization_user.id)
    end

    test "does not remove the last member" do
      organization = insert(:organization)
      user = insert(:user)
      organization_user = insert(:organization_user, organization: organization, user: user)

      assert {:error, :last_member} =
               AdminTasks.remove_organization_member(organization.name, user.username)

      assert Repo.get(OrganizationUser, organization_user.id)
    end

    test "returns an error for a nonexistent organization" do
      user = insert(:user)

      assert {:error, :organization_not_found} =
               AdminTasks.remove_organization_member("nonexistent", user.username)
    end

    test "returns an error for a nonexistent user" do
      organization = insert(:organization)

      assert {:error, :user_not_found} =
               AdminTasks.remove_organization_member(organization.name, "nonexistent")
    end

    test "returns an error when the user is not a member" do
      organization = insert(:organization)
      user = insert(:user)

      assert {:error, :member_not_found} =
               AdminTasks.remove_organization_member(organization.name, user.username)
    end
  end

  describe "allow_republish/3" do
    test "resets inserted_at timestamp for release" do
      package = insert(:package)
      old_time = ~U[2020-01-01 00:00:00Z]
      release = insert(:release, package: package, version: "1.0.0", inserted_at: old_time)

      assert :ok = AdminTasks.allow_republish(package.name, "1.0.0")

      updated_release = Repo.get!(Release, release.id)
      assert DateTime.compare(updated_release.inserted_at, old_time) == :gt
    end

    test "works with organization option" do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id)
      old_time = ~U[2020-01-01 00:00:00Z]
      release = insert(:release, package: package, version: "1.0.0", inserted_at: old_time)

      assert :ok =
               AdminTasks.allow_republish(package.name, "1.0.0", organization: repository.name)

      updated_release = Repo.get!(Release, release.id)
      assert DateTime.compare(updated_release.inserted_at, old_time) == :gt
    end

    test "returns error for nonexistent package" do
      assert {:error, :package_not_found} =
               AdminTasks.allow_republish("nonexistent", "1.0.0")
    end

    test "returns error for nonexistent release" do
      package = insert(:package)

      assert {:error, :release_not_found} =
               AdminTasks.allow_republish(package.name, "99.99.99")
    end
  end

  describe "remove_package/2" do
    test "removes package" do
      package = insert(:package)
      release = insert(:release, package: package)
      package_id = package.id
      release_id = release.id

      assert :ok = AdminTasks.remove_package("hexpm", package.name)

      refute Repo.get(Package, package_id)
      refute Repo.get(Release, release_id)
    end

    test "returns error for nonexistent repository" do
      assert {:error, :repository_not_found} =
               AdminTasks.remove_package("nonexistent_repo", "pkg")
    end

    test "returns error for nonexistent package" do
      assert {:error, :package_not_found} =
               AdminTasks.remove_package("hexpm", "nonexistent")
    end

    test "sends no email without a reason" do
      package = insert(:package)
      insert(:package_owner, package: package, user: insert(:user))

      assert :ok = AdminTasks.remove_package("hexpm", package.name)

      refute_email_sent()
    end
  end

  describe "remove_package/3 with reason" do
    test "emails every owner why the package was removed" do
      package = insert(:package)
      insert(:release, package: package)
      owner = insert(:user)
      other_owner = insert(:user)
      insert(:package_owner, package: package, user: owner)
      insert(:package_owner, package: package, user: other_owner)

      assert :ok =
               AdminTasks.remove_package("hexpm", package.name,
                 reason: "The package contains no usable code."
               )

      assert_email_sent(fn email ->
        assert Enum.sort(Enum.map(email.to, &elem(&1, 1))) ==
                 Enum.sort([User.email(owner, :primary), User.email(other_owner, :primary)])

        assert email.subject == "Hex.pm - Package #{package.name} has been removed"
        assert email.text_body =~ package.name
        assert email.text_body =~ "no usable code"
        assert email.html_body =~ "no usable code"
      end)
    end

    @tag :capture_log
    test "sends no email when the package has no owners" do
      package = insert(:package)

      assert :ok = AdminTasks.remove_package("hexpm", package.name, reason: "Spam.")

      refute_email_sent()
    end

    test "sends the canned text for a reason id" do
      package = insert(:package)
      insert(:package_owner, package: package, user: insert(:user))

      assert :ok = AdminTasks.remove_package("hexpm", package.name, reason: :seo_spam)

      assert_email_sent(fn email ->
        assert email.text_body =~ AdminTasks.reasons(:package)[:seo_spam]
      end)
    end

    test "rejects an unknown reason without deleting anything" do
      package = insert(:package)
      insert(:package_owner, package: package, user: insert(:user))
      package_id = package.id

      assert {:error, {:unknown_reason, :nonsense}} =
               AdminTasks.remove_package("hexpm", package.name, reason: :nonsense)

      assert Repo.get(Package, package_id)
      refute_email_sent()
    end

    test "rejects a reason that belongs to another scope" do
      package = insert(:package)
      package_id = package.id

      assert {:error, {:unknown_reason, :spam_account}} =
               AdminTasks.remove_package("hexpm", package.name, reason: :spam_account)

      assert Repo.get(Package, package_id)
    end

    # Every other argument here is a string, so quoting an id is the natural
    # slip, and it is the one the id lookup cannot catch.
    test "rejects a quoted reason id rather than sending it as the text" do
      package = insert(:package)
      insert(:package_owner, package: package, user: insert(:user))
      package_id = package.id

      assert {:error, {:quoted_reason_id, "seo_spam"}} =
               AdminTasks.remove_package("hexpm", package.name, reason: "seo_spam")

      assert Repo.get(Package, package_id)
      refute_email_sent()
    end

    test "rejects a blank reason" do
      package = insert(:package)
      package_id = package.id

      assert {:error, :blank_reason} =
               AdminTasks.remove_package("hexpm", package.name, reason: "   ")

      assert Repo.get(Package, package_id)
    end

    test "mails the organization when a private package has no owner rows" do
      organization = insert(:organization)
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")
      repository = insert(:repository, organization: organization)
      package = insert(:package, repository_id: repository.id, repository: repository)

      assert Repo.all(Ecto.assoc(package, :owners)) == []

      assert :ok =
               AdminTasks.remove_package(repository.name, package.name, reason: :malware)

      refute Repo.get(Package, package.id)

      assert_email_sent(fn email ->
        assert email.to == [{"", User.email(admin, :primary)}]
        assert email.text_body =~ AdminTasks.reasons(:package)[:malware]
      end)
    end

    # The admins-only filter had no fallback on this side, so an organization
    # with no admin member resolved to nobody and the mail was dropped.
    test "falls back to the members when the organization has no admin" do
      organization = insert(:organization)
      member = insert(:user)
      insert(:organization_user, organization: organization, user: member, role: "write")
      repository = insert(:repository, organization: organization)
      package = insert(:package, repository_id: repository.id, repository: repository)

      assert :ok = AdminTasks.remove_package(repository.name, package.name, reason: :malware)

      assert_email_sent(fn email ->
        assert email.to == [{"", User.email(member, :primary)}]
      end)
    end

    test "warns instead of returning a bare :ok when nobody is reachable" do
      package = insert(:package)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :ok = AdminTasks.remove_package("hexpm", package.name, reason: :seo_spam)
        end)

      assert log =~ "found no address for owners of #{package.name}"
      refute_email_sent()
    end
  end

  describe "remove_release/3" do
    test "removes release" do
      package = insert(:package)
      release = insert(:release, package: package, version: "1.0.0")
      release_id = release.id

      assert :ok = AdminTasks.remove_release("hexpm", package.name, "1.0.0")

      refute Repo.get(Release, release_id)
    end

    test "returns error for nonexistent repository" do
      assert {:error, :repository_not_found} =
               AdminTasks.remove_release("nonexistent_repo", "pkg", "1.0.0")
    end

    test "returns error for nonexistent package" do
      assert {:error, :package_not_found} =
               AdminTasks.remove_release("hexpm", "nonexistent", "1.0.0")
    end

    test "returns error for nonexistent release" do
      package = insert(:package)

      assert {:error, :release_not_found} =
               AdminTasks.remove_release("hexpm", package.name, "99.99.99")
    end

    test "sends no email without a reason" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")
      insert(:package_owner, package: package, user: insert(:user))

      assert :ok = AdminTasks.remove_release("hexpm", package.name, "1.0.0")

      refute_email_sent()
    end
  end

  describe "remove_release/4 with reason" do
    test "emails the owners why the release was removed" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")
      owner = insert(:user)
      insert(:package_owner, package: package, user: owner)

      assert :ok =
               AdminTasks.remove_release("hexpm", package.name, "1.0.0",
                 reason: "The release bundles an undisclosed credential scanner."
               )

      assert_email_sent(fn email ->
        assert email.to == [{owner.username, User.email(owner, :primary)}]
        assert email.subject == "Hex.pm - Package #{package.name} v1.0.0 has been removed"
        assert email.text_body =~ "1.0.0"
        assert email.text_body =~ "undisclosed credential scanner"
        assert email.html_body =~ "undisclosed credential scanner"
      end)
    end

    test "sends the canned text for a reason id" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")
      insert(:package_owner, package: package, user: insert(:user))

      assert :ok =
               AdminTasks.remove_release("hexpm", package.name, "1.0.0",
                 reason: :undisclosed_behaviour
               )

      assert_email_sent(fn email ->
        assert email.text_body =~ AdminTasks.reasons(:release)[:undisclosed_behaviour]
      end)
    end

    test "does not claim other versions survive when that was the only one" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")
      owner = insert(:user)
      insert(:package_owner, package: package, user: owner)

      assert :ok = AdminTasks.remove_release("hexpm", package.name, "1.0.0", reason: :malware)

      assert_email_sent(fn email ->
        refute email.text_body =~ "Other versions"
        assert email.text_body =~ "no longer has any releases"
      end)
    end

    test "says other versions are unaffected when some remain" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")
      insert(:release, package: package, version: "2.0.0")
      insert(:package_owner, package: package, user: insert(:user))

      assert :ok = AdminTasks.remove_release("hexpm", package.name, "1.0.0", reason: :malware)

      assert_email_sent(fn email ->
        assert email.text_body =~ "Other versions of the package are unaffected"
      end)
    end

    test "mails every owner, not just the first" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")
      owner = insert(:user)
      other_owner = insert(:user)
      insert(:package_owner, package: package, user: owner)
      insert(:package_owner, package: package, user: other_owner)

      assert :ok = AdminTasks.remove_release("hexpm", package.name, "1.0.0", reason: :malware)

      assert_email_sent(fn email ->
        assert Enum.sort(Enum.map(email.to, &elem(&1, 1))) ==
                 Enum.sort([User.email(owner, :primary), User.email(other_owner, :primary)])
      end)

      refute_email_sent()
    end

    test "escapes the reason in the html email" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0")
      insert(:package_owner, package: package, user: insert(:user))

      assert :ok =
               AdminTasks.remove_release("hexpm", package.name, "1.0.0",
                 reason: "<script>alert(1)</script>"
               )

      assert_email_sent(fn email ->
        refute email.html_body =~ "<script>"
        assert email.html_body =~ "&lt;script&gt;"
      end)
    end

    test "rejects an unknown reason without deleting the release" do
      package = insert(:package)
      release = insert(:release, package: package, version: "1.0.0")
      release_id = release.id

      assert {:error, {:unknown_reason, :name_squatting}} =
               AdminTasks.remove_release("hexpm", package.name, "1.0.0", reason: :name_squatting)

      assert Repo.get(Release, release_id)
    end
  end

  describe "add_owner/3" do
    test "adds owner to package" do
      package = insert(:package)
      owner = insert(:user)
      insert(:package_owner, package: package, user: owner)
      new_owner = insert(:user)

      assert {:ok, package_owner} = AdminTasks.add_owner(package.name, new_owner.username)

      assert package_owner.user_id == new_owner.id
      assert package_owner.package_id == package.id
    end

    test "adds owner with level option" do
      package = insert(:package)
      owner = insert(:user)
      insert(:package_owner, package: package, user: owner)
      new_owner = insert(:user)

      assert {:ok, package_owner} =
               AdminTasks.add_owner(package.name, new_owner.username, level: "maintainer")

      assert package_owner.level == "maintainer"
    end

    test "finds user by email" do
      package = insert(:package)
      owner = insert(:user)
      insert(:package_owner, package: package, user: owner)
      email = Fake.sequence(:email)
      new_owner = insert(:user, emails: [build(:email, email: email)])

      assert {:ok, package_owner} = AdminTasks.add_owner(package.name, email)

      assert package_owner.user_id == new_owner.id
    end
  end

  describe "remove_owner/2" do
    test "removes owner from package" do
      package = insert(:package)
      owner1 = insert(:user)
      owner2 = insert(:user)
      insert(:package_owner, package: package, user: owner1)
      insert(:package_owner, package: package, user: owner2)

      assert :ok = AdminTasks.remove_owner(package.name, owner2.username)

      owners = Repo.all(Ecto.assoc(package, :package_owners))
      assert length(owners) == 1
      assert hd(owners).user_id == owner1.id
    end

    test "returns error when not an owner" do
      package = insert(:package)
      owner = insert(:user)
      insert(:package_owner, package: package, user: owner)
      non_owner = insert(:user)

      assert {:error, :not_owner} = AdminTasks.remove_owner(package.name, non_owner.username)
    end

    test "returns error when trying to remove last owner" do
      package = insert(:package)
      owner = insert(:user)
      insert(:package_owner, package: package, user: owner)

      assert {:error, :last_owner} = AdminTasks.remove_owner(package.name, owner.username)
    end
  end

  describe "rename_organization/2" do
    test "renames organization" do
      organization = insert(:organization, name: "old_org")

      assert :ok = AdminTasks.rename_organization("old_org", "new_org")

      updated_org = Repo.get!(Organization, organization.id)
      assert updated_org.name == "new_org"
    end

    test "updates organization user's username" do
      organization = insert(:organization, name: "old_org")

      assert :ok = AdminTasks.rename_organization("old_org", "new_org")

      updated_org = Repo.get!(Organization, organization.id) |> Repo.preload(:user)
      assert updated_org.user.username == "new_org"
    end

    test "returns error for nonexistent organization" do
      assert {:error, :organization_not_found} =
               AdminTasks.rename_organization("nonexistent", "new_name")
    end
  end

  describe "add_install/2" do
    test "adds new install record" do
      initial_count = Repo.aggregate(Hexpm.Repository.Install, :count)

      assert :ok = AdminTasks.add_install("2.0.0", ["1.14.0", "1.15.0"])

      new_count = Repo.aggregate(Hexpm.Repository.Install, :count)
      assert new_count == initial_count + 1

      install = Repo.one(from i in Hexpm.Repository.Install, order_by: [desc: i.id], limit: 1)
      assert install.hex == "2.0.0"
      assert install.elixirs == ["1.14.0", "1.15.0"]
    end

    test "works with nil hex_version (just uploads)" do
      assert :ok = AdminTasks.add_install(nil, [])
    end
  end

  describe "security_password_reset/2" do
    test "sends password reset email" do
      user = insert(:user)

      assert :ok = AdminTasks.security_password_reset(user.username)

      # Verify password reset record was created
      user = Repo.preload(user, :password_resets, force: true)
      assert length(user.password_resets) == 1
    end

    test "finds user by email" do
      email = Fake.sequence(:email)
      user = insert(:user, emails: [build(:email, email: email)])

      assert :ok = AdminTasks.security_password_reset(email)

      user = Repo.preload(user, :password_resets, force: true)
      assert length(user.password_resets) == 1
    end

    test "returns error for nonexistent user" do
      assert {:error, :user_not_found} = AdminTasks.security_password_reset("nonexistent")
    end

    test "returns error for organization user" do
      organization = insert(:organization)

      assert {:error, :organization_user} =
               AdminTasks.security_password_reset(organization.user.username)
    end

    test "disable_password option sets password to nil" do
      user = insert(:user)
      assert user.password != nil

      assert :ok = AdminTasks.security_password_reset(user.username, disable_password: true)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.password == nil
    end

    test "revoke_all_access option revokes keys and sessions" do
      user = insert(:user)
      key = insert(:key, user: user)
      session = insert(:session, user_id: user.id)

      assert :ok = AdminTasks.security_password_reset(user.username, revoke_all_access: true)

      # Verify key was revoked
      updated_key = Repo.get!(Hexpm.Accounts.Key, key.id)
      assert updated_key.revoke_at != nil

      # Verify session was revoked
      updated_session = Repo.get!(Hexpm.UserSession, session.id)
      assert updated_session.revoked_at != nil
    end

    test "combines both options" do
      user = insert(:user)
      key = insert(:key, user: user)

      assert :ok =
               AdminTasks.security_password_reset(user.username,
                 disable_password: true,
                 revoke_all_access: true
               )

      updated_user = Repo.get!(User, user.id)
      assert updated_user.password == nil

      updated_key = Repo.get!(Hexpm.Accounts.Key, key.id)
      assert updated_key.revoke_at != nil
    end
  end

  describe "retry_oban_jobs/1" do
    alias Hexpm.Hexdocs.Workers

    test "retries discarded jobs at priority 8" do
      discarded = insert_discarded_job(Workers.Upload, %{key: "docs/retried-1.0.0.tar.gz"})
      {:ok, available} = Oban.insert(Workers.Upload.new(%{key: "docs/untouched-1.0.0.tar.gz"}))

      assert {:ok, 1} = AdminTasks.retry_oban_jobs()

      retried = Repo.get!(Oban.Job, discarded.id)
      assert retried.state == "available"
      assert retried.priority == 8

      # A job that was never discarded is left alone.
      assert Repo.get!(Oban.Job, available.id).state == "available"
    end

    test "with uniq: true retries one job per worker and args" do
      insert_discarded_job(Workers.Upload, %{key: "docs/dup-1.0.0.tar.gz"})
      insert_discarded_job(Workers.Upload, %{key: "docs/dup-1.0.0.tar.gz"})

      assert {:ok, 1} = AdminTasks.retry_oban_jobs(uniq: true)

      assert Repo.aggregate(available_uploads(), :count) == 1
      assert Repo.aggregate(discarded_uploads(), :count) == 1
    end

    test "without uniq retries every discarded job" do
      insert_discarded_job(Workers.Upload, %{key: "docs/dup-1.0.0.tar.gz"})
      insert_discarded_job(Workers.Upload, %{key: "docs/dup-1.0.0.tar.gz"})

      assert {:ok, 2} = AdminTasks.retry_oban_jobs()

      assert Repo.aggregate(available_uploads(), :count) == 2
    end

    test "retries only the given worker" do
      insert_discarded_job(Workers.Upload, %{key: "docs/filtered-1.0.0.tar.gz"})
      search = insert_discarded_job(Workers.Search, %{key: "docs/filtered-1.0.0.tar.gz"})

      assert {:ok, 1} = AdminTasks.retry_oban_jobs(worker: "Hexpm.Hexdocs.Workers.Upload")

      assert Repo.aggregate(available_uploads(), :count) == 1
      assert Repo.get!(Oban.Job, search.id).state == "discarded"
    end

    defp insert_discarded_job(worker, args) do
      {:ok, job} = Oban.insert(worker.new(args))

      {1, _} =
        from(j in Oban.Job, where: j.id == ^job.id)
        |> Repo.update_all(
          set: [
            state: "discarded",
            attempt: job.max_attempts,
            discarded_at: DateTime.utc_now()
          ]
        )

      job
    end

    defp available_uploads do
      from(j in Oban.Job,
        where: j.worker == "Hexpm.Hexdocs.Workers.Upload" and j.state == "available"
      )
    end

    defp discarded_uploads do
      from(j in Oban.Job,
        where: j.worker == "Hexpm.Hexdocs.Workers.Upload" and j.state == "discarded"
      )
    end
  end

  describe "send_email/3" do
    test "queues a separate email for each recipient" do
      assert {:ok, 2} =
               AdminTasks.send_email(
                 ["bob@example.com", "jane@example.com"],
                 "Hex.pm - Service update",
                 "First paragraph.\n\nSecond paragraph."
               )

      assert Enum.map(Repo.all(OutboxEntry), & &1.category) == [
               "admin.announcement",
               "admin.announcement"
             ]

      deliver_queued_emails()

      assert_email_sent(fn email ->
        assert email.to == [{"", "bob@example.com"}]
        assert email.subject == "Hex.pm - Service update"
        assert email.text_body =~ "First paragraph."
        assert email.text_body =~ "Second paragraph."
        assert email.html_body =~ "Service update"
        assert email.html_body =~ "<p"
      end)

      assert_email_sent(fn email -> assert email.to == [{"", "jane@example.com"}] end)
    end

    test "queues announcements behind transactional mail" do
      assert {:ok, 1} =
               AdminTasks.send_email(["bob@example.com"], "Hex.pm - Service update", "Body")

      assert [entry] = Repo.all(OutboxEntry)
      assert entry.priority == 3
      assert entry.group_key == "admin.announcement:Hex.pm - Service update"

      assert [%Oban.Job{priority: 3}] =
               Repo.all(
                 from(job in Oban.Job,
                   where: job.worker == "Hexpm.Emails.OutboxWorker",
                   where: job.args == ^%{"outbox_entry_id" => entry.id}
                 )
               )
    end

    test "skips recipients that already have this announcement queued or delivered" do
      assert {:ok, 2} =
               AdminTasks.send_email(
                 ["bob@example.com", "jane@example.com"],
                 "Hex.pm - Service update",
                 "Body"
               )

      [first | _] = Repo.all(OutboxEntry)
      assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: first.id})

      assert {:ok, 1} =
               AdminTasks.send_email(
                 ["bob@example.com", "jane@example.com", "joe@example.com"],
                 "Hex.pm - Service update",
                 "Body"
               )

      assert Enum.sort(Enum.flat_map(Repo.all(OutboxEntry), & &1.recipients)) == [
               "bob@example.com",
               "jane@example.com",
               "joe@example.com"
             ]

      assert {:ok, 2} =
               AdminTasks.send_email(
                 ["bob@example.com", "jane@example.com"],
                 "Hex.pm - Another update",
                 "Body"
               )
    end

    test "a queued announcement can be cancelled by its group key" do
      assert {:ok, 2} =
               AdminTasks.send_email(
                 ["bob@example.com", "jane@example.com"],
                 "Hex.pm - Service update",
                 "Body"
               )

      assert Hexpm.Emails.Outbox.cancel!(
               group_key: "admin.announcement:Hex.pm - Service update",
               categories: ["admin.announcement"]
             ) == 2

      assert Repo.all(OutboxEntry) == []
    end

    test "only queues once for duplicate recipients" do
      assert {:ok, 1} =
               AdminTasks.send_email(
                 ["bob@example.com", "bob@example.com"],
                 "Hex.pm - Service update",
                 "Body"
               )

      assert length(Repo.all(OutboxEntry)) == 1
    end

    test "escapes the body in the html email" do
      assert {:ok, 1} =
               AdminTasks.send_email(["bob@example.com"], "Subject", "<script>alert(1)</script>")

      deliver_queued_emails()

      assert_email_sent(fn email ->
        refute email.html_body =~ "<script>"
        assert email.html_body =~ "&lt;script&gt;"
      end)
    end

    test "links bare urls in the html email and leaves the text body alone" do
      assert {:ok, 1} =
               AdminTasks.send_email(
                 ["bob@example.com"],
                 "Subject",
                 "Read https://hex.pm/policies/termsofservice."
               )

      deliver_queued_emails()

      assert_email_sent(fn email ->
        assert email.html_body =~
                 ~s(<a href="https://hex.pm/policies/termsofservice" style="color: #0f59d8; text-decoration: none;">https://hex.pm/policies/termsofservice</a>.)

        assert email.text_body =~ "Read https://hex.pm/policies/termsofservice."
      end)
    end

    test "keeps single newlines as line breaks in the html email" do
      assert {:ok, 1} =
               AdminTasks.send_email(
                 ["bob@example.com"],
                 "Subject",
                 "Read them here:\n\nhttps://hex.pm/policies/termsofservice\nhttps://hex.pm/policies/privacy"
               )

      deliver_queued_emails()

      assert_email_sent(fn email ->
        assert email.html_body =~
                 ~r{termsofservice</a><br>\s*<a href="https://hex.pm/policies/privacy"}

        assert email.html_body =~ ~r{Read them here:\s*</p>}

        assert email.text_body =~
                 "https://hex.pm/policies/termsofservice\nhttps://hex.pm/policies/privacy"
      end)
    end
  end

  defp deliver_queued_emails() do
    for entry <- Repo.all(OutboxEntry) do
      assert :ok = perform_job(OutboxWorker, %{outbox_entry_id: entry.id})
    end
  end
end

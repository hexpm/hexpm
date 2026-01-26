defmodule Hexpm.AdminTasksTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.AdminTasks
  alias Hexpm.Accounts.{Organization, User}
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
end

defmodule Hexpm.Accounts.KeysTest do
  use Hexpm.DataCase, async: true
  import Swoosh.TestAssertions

  alias Hexpm.Accounts.{Key, KeyGrantor, Keys, User}

  setup do
    user = insert(:user_with_tfa)
    organization = insert(:organization)

    package =
      insert(:package,
        package_owners: [
          build(:package_owner, user: user),
          build(:package_owner, user: organization.user)
        ]
      )

    %{
      user: user,
      organization: organization,
      package: package
    }
  end

  describe "create/2 token format" do
    test "new keys have v2 token format", %{user: user} do
      params = %{"name" => "keyname", "permissions" => [%{"domain" => "api"}]}
      assert {:ok, %{key: key}} = Keys.create(user, params, audit: audit_data(user))
      assert key.token_format == "v2"
    end

    test "new key user_secret has hex_ prefix", %{user: user} do
      params = %{"name" => "keyname", "permissions" => [%{"domain" => "api"}]}
      assert {:ok, %{key: key}} = Keys.create(user, params, audit: audit_data(user))
      assert String.starts_with?(key.user_secret, "hex_")
    end

    test "user_secret body is 40 lowercase hex chars (32 random + 8 CRC32)", %{user: user} do
      params = %{"name" => "keyname", "permissions" => [%{"domain" => "api"}]}
      assert {:ok, %{key: key}} = Keys.create(user, params, audit: audit_data(user))
      assert "hex_" <> body = key.user_secret
      assert String.length(body) == 40
      assert body =~ ~r/^[a-f0-9]{40}$/
    end
  end

  describe "create/2 with revoke_at" do
    test "create key with future revoke_at", %{user: user} do
      revoke_at = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

      params = %{
        "name" => "expiring-key",
        "permissions" => [%{"domain" => "api"}],
        "revoke_at" => revoke_at
      }

      assert {:ok, %{key: key}} = Keys.create(user, params, audit: audit_data(user))
      assert key.name == "expiring-key"
      assert DateTime.compare(key.revoke_at, DateTime.utc_now()) == :gt
    end

    test "create key with past revoke_at fails validation", %{user: user} do
      revoke_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      params = %{
        "name" => "expired-key",
        "permissions" => [%{"domain" => "api"}],
        "revoke_at" => revoke_at
      }

      assert {:error, :key, changeset, _} = Keys.create(user, params, audit: audit_data(user))
      assert errors_on(changeset)[:revoke_at] == "must be in the future"
    end
  end

  describe "create/2" do
    test "user api permissions", %{user: user} do
      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "api", "resource" => "read"}]
      }

      assert {:ok, %{key: key}} = Keys.create(user, params, audit: audit_data(user))
      assert key.name == "keyname"
      assert key.user_id == user.id
      assert "hex_" <> raw = key.user_secret
      assert {:ok, _} = Base.decode16(raw, case: :lower)
    end

    test "organization api permissions", %{organization: organization} do
      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "api", "resource" => "read"}]
      }

      assert {:ok, %{key: key}} =
               Keys.create(organization, params, audit: audit_data(organization))

      assert key.name == "keyname"
      assert key.organization_id == organization.id
      assert "hex_" <> raw = key.user_secret
      assert {:ok, _} = Base.decode16(raw, case: :lower)
    end

    test "user repository permissions are not allowed", %{user: user, organization: organization} do
      insert(:organization_user, organization: organization, user: user)

      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "repository", "resource" => organization.name}]
      }

      assert {:error, :key, changeset, _} = Keys.create(user, params, audit: audit_data(user))

      assert errors_on(changeset)[:permissions][:domain] ==
               "user keys cannot have repository permissions, generate an organization key instead"

      params = %{"name" => "keyname", "permissions" => [%{"domain" => "repositories"}]}

      assert {:error, :key, changeset, _} = Keys.create(user, params, audit: audit_data(user))

      assert errors_on(changeset)[:permissions][:domain] ==
               "user keys cannot have repository permissions, generate an organization key instead"
    end

    test "organization repository permissions", %{organization: organization} do
      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "repository", "resource" => organization.name}]
      }

      assert {:ok, %{key: key}} =
               Keys.create(organization, params, audit: audit_data(organization))

      assert key.organization_id == organization.id
    end

    test "user package permissions", %{user: user, package: package} do
      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "package", "resource" => package.name}]
      }

      assert {:ok, %{key: %Key{}}} = Keys.create(user, params, audit: audit_data(user))

      unowned_package = insert(:package)

      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "package", "resource" => unowned_package.name}]
      }

      assert {:error, :key, changeset, _} = Keys.create(user, params, audit: audit_data(user))

      assert errors_on(changeset)[:permissions][:resource] ==
               "you do not have access to this package"

      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "package", "resource" => "NON_EXISTANT_PACKAGE"}]
      }

      assert {:error, :key, changeset, _} = Keys.create(user, params, audit: audit_data(user))

      assert errors_on(changeset)[:permissions][:resource] ==
               "you do not have access to this package"
    end

    test "package permission without a resource", %{user: user} do
      params = %{"name" => "keyname", "permissions" => [%{"domain" => "package"}]}

      assert {:error, :key, changeset, _} = Keys.create(user, params, audit: audit_data(user))
      assert errors_on(changeset)[:permissions][:resource] == "can't be blank"
    end

    test "organization package permissions" do
      repository = insert(:repository)
      organization = repository.organization
      package = insert(:package, repository_id: repository.id)

      # The organization owns every package in its own repository, even when the
      # organization's backing user is not an explicit package owner.
      refute Hexpm.Repository.Packages.owner_with_access?(
               %{package | repository: repository},
               organization.user
             )

      params = %{
        "name" => "keyname",
        "permissions" => [
          %{"domain" => "package", "resource" => "#{organization.name}/#{package.name}"}
        ]
      }

      assert {:ok, %{key: %Key{}}} =
               Keys.create(organization, params, audit: audit_data(organization))

      # A package in another repository is not accessible to this organization.
      other_package = insert(:package)

      params = %{
        "name" => "keyname",
        "permissions" => [
          %{"domain" => "package", "resource" => "#{organization.name}/#{other_package.name}"}
        ]
      }

      assert {:error, :key, changeset, _} =
               Keys.create(organization, params, audit: audit_data(organization))

      assert errors_on(changeset)[:permissions][:resource] ==
               "you do not have access to this package"

      # A package qualified with another organization's name is not accessible.
      params = %{
        "name" => "keyname",
        "permissions" => [
          %{"domain" => "package", "resource" => "other-org/#{package.name}"}
        ]
      }

      assert {:error, :key, changeset, _} =
               Keys.create(organization, params, audit: audit_data(organization))

      assert errors_on(changeset)[:permissions][:resource] ==
               "you do not have access to this package"

      params = %{
        "name" => "keyname",
        "permissions" => [
          %{"domain" => "package", "resource" => "#{organization.name}/NON_EXISTANT_PACKAGE"}
        ]
      }

      assert {:error, :key, changeset, _} =
               Keys.create(organization, params, audit: audit_data(organization))

      assert errors_on(changeset)[:permissions][:resource] ==
               "you do not have access to this package"
    end
  end

  describe "personal_reaching_organization/1" do
    test "lists a member's key with a package permission without a resource", %{
      user: user,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user)

      insert(:key,
        user: user,
        name: "every-package",
        permissions: [build(:key_permission, domain: "package")]
      )

      insert(:key,
        user: user,
        name: "other-organization",
        permissions: [build(:key_permission, domain: "repository", resource: "other")]
      )

      assert Enum.map(Keys.personal_reaching_organization(organization), & &1.name) ==
               ["every-package"]
    end
  end

  describe "create/2 without two-factor authentication" do
    setup %{package: package} do
      user = insert(:user)
      insert(:package_owner, package: package, user: user)
      %{user: user}
    end

    test "refuses every permission that can publish", %{user: user, package: package} do
      for permission <- [
            %{"domain" => "api"},
            %{"domain" => "api", "resource" => "write"},
            %{"domain" => "publish"},
            %{"domain" => "publish", "resource" => package.name},
            %{"domain" => "package", "resource" => package.name}
          ] do
        params = %{"name" => "keyname", "permissions" => [permission]}
        assert {:error, :key, changeset, _} = Keys.create(user, params, audit: audit_data(user))

        assert errors_on(changeset)[:permissions][:domain] =~
                 "requires two-factor authentication on your account"
      end
    end

    test "refuses the default permission", %{user: user} do
      assert {:error, :key, changeset, _} =
               Keys.create(user, %{"name" => "keyname"}, audit: audit_data(user))

      assert errors_on(changeset)[:permissions][:domain] ==
               "api requires two-factor authentication on your account"
    end

    test "allows permissions that can't publish", %{user: user, package: package} do
      for permission <- [
            %{"domain" => "api", "resource" => "read"},
            %{"domain" => "owners"},
            %{"domain" => "owners", "resource" => package.name}
          ] do
        params = %{"name" => "keyname", "permissions" => [permission]}
        assert {:ok, _} = Keys.create(user, params, audit: audit_data(user))
      end
    end

    test "refuses a write member's organization key that publishes", %{
      user: user,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user, role: "write")
      grantor = KeyGrantor.new(organization, user, nil)

      params = %{"name" => "keyname", "permissions" => [%{"domain" => "api"}]}

      assert {:error, :key, changeset, _} =
               Keys.create(organization, params, audit: audit_data(user), grantor: grantor)

      assert errors_on(changeset)[:permissions][:domain] ==
               "publish requires two-factor authentication on your account"

      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "repository", "resource" => organization.name}]
      }

      assert {:ok, _} =
               Keys.create(organization, params, audit: audit_data(user), grantor: grantor)
    end
  end

  describe "optional emails" do
    @params %{"name" => "keyname", "permissions" => [%{"domain" => "api", "resource" => "read"}]}

    test "a user who turned off key emails gets none" do
      user = insert(:user, optional_emails: %{"api_keys" => false})

      assert {:ok, _} = Keys.create(user, @params, audit: audit_data(user))
      assert {:ok, _} = Keys.revoke(user, "keyname", audit: audit_data(user))
      assert {:ok, _} = Keys.create(user, @params, audit: audit_data(user))
      assert {:ok, _} = Keys.revoke_all(user, audit: audit_data(user))
      assert_no_email_sent()
    end

    test "organization admins who turned them off are left out" do
      opted_out = insert(:user, optional_emails: %{"api_keys" => false})
      admin = insert(:user)

      organization =
        insert(:organization,
          organization_users: [
            build(:organization_user, user: opted_out, role: "admin"),
            build(:organization_user, user: admin, role: "admin")
          ]
        )

      assert {:ok, _} = Keys.create(organization, @params, audit: audit_data(admin))

      assert_email_sent(fn email ->
        assert email.subject =~ "A new key was created"
        assert email.to == [{"", User.email(admin, :primary)}]
      end)
    end

    test "an organization whose admins all turned them off sends none" do
      opted_out = insert(:user, optional_emails: %{"api_keys" => false})

      organization =
        insert(:organization,
          organization_users: [build(:organization_user, user: opted_out, role: "admin")]
        )

      assert {:ok, _} = Keys.create(organization, @params, audit: audit_data(opted_out))
      assert_no_email_sent()
    end
  end
end

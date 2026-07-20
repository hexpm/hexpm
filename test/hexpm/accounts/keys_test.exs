defmodule Hexpm.Accounts.KeysTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{Key, Keys}

  setup do
    user = insert(:user)
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
      assert {:ok, _} = Base.decode16(key.user_secret, case: :lower)
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
      assert {:ok, _} = Base.decode16(key.user_secret, case: :lower)
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
end

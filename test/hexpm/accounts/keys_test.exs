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

    test "organization package permissions", %{organization: organization, package: package} do
      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "package", "resource" => package.name}]
      }

      assert {:ok, %{key: %Key{}}} =
               Keys.create(organization, params, audit: audit_data(organization))

      unowned_package = insert(:package)

      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "package", "resource" => unowned_package.name}]
      }

      assert {:error, :key, changeset, _} =
               Keys.create(organization, params, audit: audit_data(organization))

      assert errors_on(changeset)[:permissions][:resource] ==
               "you do not have access to this package"

      params = %{
        "name" => "keyname",
        "permissions" => [%{"domain" => "package", "resource" => "NON_EXISTANT_PACKAGE"}]
      }

      assert {:error, :key, changeset, _} =
               Keys.create(organization, params, audit: audit_data(organization))

      assert errors_on(changeset)[:permissions][:resource] ==
               "you do not have access to this package"
    end
  end
end

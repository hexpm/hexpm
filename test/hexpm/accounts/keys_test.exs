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

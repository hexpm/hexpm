defmodule Hexpm.PermissionsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Permissions
  alias Hexpm.OAuth.Token
  alias Hexpm.Repository.Package

  describe "validate_scopes/1" do
    test "accepts valid simple scopes" do
      assert :ok = Permissions.validate_scopes(["api"])
      assert :ok = Permissions.validate_scopes(["api:read"])
      assert :ok = Permissions.validate_scopes(["api:write"])
      assert :ok = Permissions.validate_scopes(["repositories"])
      # package, repository, and docs are only valid with resources now
    end

    test "accepts valid resource-specific scopes" do
      assert :ok = Permissions.validate_scopes(["package:hexpm/decimal"])
      assert :ok = Permissions.validate_scopes(["repository:acme"])
      assert :ok = Permissions.validate_scopes(["package:myorg/mypackage"])
      assert :ok = Permissions.validate_scopes(["docs:hexpm"])
    end

    test "rejects invalid scopes" do
      assert {:error, _} = Permissions.validate_scopes(["invalid"])
      assert {:error, _} = Permissions.validate_scopes(["api:invalid"])
      assert {:error, _} = Permissions.validate_scopes(["unknown:resource"])
      # package, repository, and docs require resources
      assert {:error, _} = Permissions.validate_scopes(["package"])
      assert {:error, _} = Permissions.validate_scopes(["repository"])
      assert {:error, _} = Permissions.validate_scopes(["docs"])
    end

    test "accepts mixed valid scopes" do
      assert :ok =
               Permissions.validate_scopes([
                 "api:read",
                 "package:hexpm/decimal",
                 "repository:acme",
                 "repositories"
               ])
    end
  end

  describe "resource-specific package scopes" do
    setup do
      repository = %{name: "hexpm"}
      package = %Package{name: "decimal", repository: repository}
      {:ok, package: package}
    end

    test "package:hexpm/decimal scope only allows access to specific package", %{package: package} do
      token = %Token{scopes: ["package:hexpm/decimal"]}

      # Should allow access to the specific package
      assert Permissions.verify_access?(token, "package", package)

      # Should not allow access to other packages
      other_package = %Package{name: "poison", repository: %{name: "hexpm"}}
      refute Permissions.verify_access?(token, "package", other_package)

      # Should not allow access to packages in other orgs
      org_package = %Package{name: "decimal", repository: %{name: "myorg"}}
      refute Permissions.verify_access?(token, "package", org_package)

      # Should not grant API access
      refute Permissions.verify_access?(token, "api", "read")
      refute Permissions.verify_access?(token, "api", "write")
    end

    # Removed test for unrestricted package scope since it's no longer supported

    test "multiple package scopes grant access to multiple packages", %{package: package} do
      token = %Token{scopes: ["package:hexpm/decimal", "package:hexpm/poison"]}

      # Should allow access to both specified packages
      assert Permissions.verify_access?(token, "package", package)

      poison_package = %Package{name: "poison", repository: %{name: "hexpm"}}
      assert Permissions.verify_access?(token, "package", poison_package)

      # Should not allow access to other packages
      other_package = %Package{name: "phoenix", repository: %{name: "hexpm"}}
      refute Permissions.verify_access?(token, "package", other_package)
    end
  end

  describe "resource-specific repository scopes" do
    test "repository:acme scope only allows access to specific repository" do
      token = %Token{scopes: ["repository:acme"]}

      # Should allow access to the specific repository
      assert Permissions.verify_access?(token, "repository", "acme")

      # Should not allow access to other repositories
      refute Permissions.verify_access?(token, "repository", "other")

      # Should not grant repositories access
      refute Permissions.verify_access?(token, "repositories", nil)
    end

    test "repositories scope allows access to all repositories" do
      token = %Token{scopes: ["repositories"]}

      # Should allow access to any repository
      assert Permissions.verify_access?(token, "repository", "acme")
      assert Permissions.verify_access?(token, "repository", "other")
      assert Permissions.verify_access?(token, "repositories", nil)
    end

    test "multiple repository scopes grant access to multiple repositories" do
      token = %Token{scopes: ["repository:acme", "repository:beta"]}

      # Should allow access to both specified repositories
      assert Permissions.verify_access?(token, "repository", "acme")
      assert Permissions.verify_access?(token, "repository", "beta")

      # Should not allow access to other repositories
      refute Permissions.verify_access?(token, "repository", "gamma")
    end
  end

  describe "scope_to_permission and permission_to_scope conversions" do
    test "correctly converts resource-specific package scopes" do
      scope = "package:hexpm/decimal"
      perm = Permissions.scope_to_permission(scope)

      assert perm == %{domain: "package", resource: "hexpm/decimal"}
      assert Permissions.permission_to_scope(perm) == scope
    end

    test "correctly converts resource-specific repository scopes" do
      scope = "repository:acme"
      perm = Permissions.scope_to_permission(scope)

      assert perm == %{domain: "repository", resource: "acme"}
      assert Permissions.permission_to_scope(perm) == scope
    end

    test "correctly converts simple scopes" do
      assert Permissions.scope_to_permission("api") == %{domain: "api", resource: nil}

      assert Permissions.scope_to_permission("repositories") == %{
               domain: "repositories",
               resource: nil
             }
    end

    test "round-trip conversion preserves scope" do
      scopes = [
        "api",
        "api:read",
        "api:write",
        "package:hexpm/decimal",
        "repository:acme",
        "repositories"
      ]

      for scope <- scopes do
        perm = Permissions.scope_to_permission(scope)
        assert Permissions.permission_to_scope(perm) == scope
      end
    end
  end

  describe "verify_access? with KeyPermissions" do
    test "verifies repository permissions" do
      key = build(:key, permissions: [build(:key_permission, domain: "repositories")])
      refute Permissions.verify_access?(key, "api", "read")
      refute Permissions.verify_access?(key, "api", "write")
      assert Permissions.verify_access?(key, "repository", "foo")
      assert Permissions.verify_access?(key, "repositories", nil)

      key =
        build(:key, permissions: [build(:key_permission, domain: "repository", resource: "foo")])

      refute Permissions.verify_access?(key, "api", "read")
      refute Permissions.verify_access?(key, "api", "write")
      assert Permissions.verify_access?(key, "repository", "foo")
      refute Permissions.verify_access?(key, "repository", "bar")
      refute Permissions.verify_access?(key, "repositories", nil)
    end

    test "verifies docs permissions" do
      key = build(:key, permissions: [build(:key_permission, domain: "docs", resource: "foo")])
      refute Permissions.verify_access?(key, "api", "read")
      refute Permissions.verify_access?(key, "api", "write")
      assert Permissions.verify_access?(key, "docs", "foo")
      refute Permissions.verify_access?(key, "docs", "bar")
      refute Permissions.verify_access?(key, "repositories", nil)
    end

    test "verifies api permissions" do
      key = build(:key, permissions: [build(:key_permission, domain: "api")])
      assert Permissions.verify_access?(key, "api", "read")
      assert Permissions.verify_access?(key, "api", "write")
      refute Permissions.verify_access?(key, "repository", "foo")
      refute Permissions.verify_access?(key, "repositories", nil)

      key = build(:key, permissions: [build(:key_permission, domain: "api", resource: "read")])
      assert Permissions.verify_access?(key, "api", "read")
      refute Permissions.verify_access?(key, "api", "write")
      refute Permissions.verify_access?(key, "repository", "foo")
      refute Permissions.verify_access?(key, "repositories", nil)

      key = build(:key, permissions: [build(:key_permission, domain: "api", resource: "write")])
      assert Permissions.verify_access?(key, "api", "read")
      assert Permissions.verify_access?(key, "api", "write")
      refute Permissions.verify_access?(key, "repository", "foo")
      refute Permissions.verify_access?(key, "repositories", nil)
    end
  end

  describe "scope_description/1" do
    test "provides descriptions for all basic scopes" do
      assert Permissions.scope_description("api") =~ "Complete access"
      assert Permissions.scope_description("api:read") =~ "Read-only access"
      assert Permissions.scope_description("api:write") =~ "Read and write access"
      assert Permissions.scope_description("repositories") =~ "private repositories"
      # package and docs are no longer simple scopes - they require resources
    end

    test "provides descriptions for resource-specific scopes" do
      assert Permissions.scope_description("package:hexpm/decimal") ==
               "Manage the hexpm/decimal package"

      assert Permissions.scope_description("repository:acme") ==
               "Access to the acme private repository"

      assert Permissions.scope_description("docs:hexpm/decimal") ==
               "Fetch documentation for the hexpm/decimal organization"
    end

    test "raises error for unknown scopes" do
      assert_raise ArgumentError, ~r/Unknown scope: invalid/, fn ->
        Permissions.scope_description("invalid")
      end

      assert_raise ArgumentError, ~r/Unknown scope: unknown:resource/, fn ->
        Permissions.scope_description("unknown:resource")
      end
    end

    test "handles edge cases" do
      # Complex package names
      assert Permissions.scope_description("package:myorg/my_complex-package.name") ==
               "Manage the myorg/my_complex-package.name package"

      # Test that simple package/repository/docs scopes are rejected
      assert_raise ArgumentError, ~r/Unknown scope: package/, fn ->
        Permissions.scope_description("package")
      end

      assert_raise ArgumentError, ~r/Unknown scope: repository/, fn ->
        Permissions.scope_description("repository")
      end

      assert_raise ArgumentError, ~r/Unknown scope: docs/, fn ->
        Permissions.scope_description("docs")
      end
    end
  end
end

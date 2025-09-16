defmodule Hexpm.Permissions do
  @moduledoc """
  Unified permission system for API keys and OAuth tokens.

  This module provides a single source of truth for scope definitions and
  verification logic, consolidating the previously duplicated permission
  systems used by KeyPermission and OAuth tokens.
  """

  alias Hexpm.Accounts.{Key, KeyPermission, User, Organization}
  alias Hexpm.OAuth.Token
  alias Hexpm.Repository.Package

  # Consolidated scope definitions - single source of truth
  @api_scopes ~w(api api:read api:write)
  @resource_scopes ~w(repositories package repository docs)
  @all_scopes @api_scopes ++ @resource_scopes

  # Legacy domain list for KeyPermission compatibility
  @legacy_domains ~w(api package repository repositories docs)

  @doc """
  Returns all valid scopes for OAuth tokens.
  """
  def valid_scopes, do: @all_scopes

  @doc """
  Returns all valid domains for KeyPermissions (legacy format).
  """
  def valid_domains, do: @legacy_domains

  @doc """
  Validates a list of scopes against the allowed scope definitions.
  """
  def validate_scopes(scopes) when is_list(scopes) do
    invalid_scopes = Enum.reject(scopes, &(&1 in @all_scopes))

    case invalid_scopes do
      [] -> :ok
      _ -> {:error, "contains invalid scopes: #{Enum.join(invalid_scopes, ", ")}"}
    end
  end

  @doc """
  Validates a domain against the allowed domain definitions.
  """
  def validate_domain(domain) when is_binary(domain) do
    if domain in @legacy_domains do
      :ok
    else
      {:error, "invalid domain"}
    end
  end

  @doc """
  Converts a KeyPermission to a scope string format.

  Examples:
  - %{domain: "api", resource: "read"} -> "api:read"
  - %{domain: "api", resource: nil} -> "api"
  - %{domain: "package", resource: "hexpm/poison"} -> "package"
  """
  def permission_to_scope(%{domain: domain, resource: resource}) do
    case {domain, resource} do
      {"api", nil} -> "api"
      {"api", resource} when resource in ["read", "write"] -> "#{domain}:#{resource}"
      {domain, _} -> domain
    end
  end

  @doc """
  Converts a scope string to KeyPermission format.

  Examples:
  - "api:read" -> %{domain: "api", resource: "read"}
  - "api" -> %{domain: "api", resource: nil}
  - "package" -> %{domain: "package", resource: nil}
  """
  def scope_to_permission(scope) when is_binary(scope) do
    case String.split(scope, ":", parts: 2) do
      [domain] -> %{domain: domain, resource: nil}
      [domain, resource] -> %{domain: domain, resource: resource}
    end
  end

  @doc """
  Unified permission verification for both Keys and OAuth tokens.

  This function handles the complex permission matching logic that was
  previously duplicated between Key.verify_permissions?/3 and
  Token.verify_permissions?/3.
  """
  def verify_access?(permissions, domain, resource) when is_list(permissions) do
    normalized_permissions = normalize_permissions(permissions)
    check_access?(normalized_permissions, domain, resource)
  end

  def verify_access?(%Key{} = key, domain, resource) do
    verify_access?(key.permissions, domain, resource)
  end

  def verify_access?(%Token{} = token, domain, resource) do
    verify_access?(token.scopes, domain, resource)
  end

  @doc """
  Normalizes permissions from different formats into a unified structure.

  Handles both KeyPermission format (%{domain: "api", resource: "read"})
  and OAuth scope format (["api:read"]).
  """
  def normalize_permissions(permissions) when is_list(permissions) do
    Enum.map(permissions, &normalize_permission/1)
  end

  defp normalize_permission(%KeyPermission{domain: domain, resource: resource}) do
    %{domain: domain, resource: resource, scope: permission_to_scope(%{domain: domain, resource: resource}), is_oauth_scope: false}
  end

  defp normalize_permission(%{domain: domain, resource: resource}) do
    %{domain: domain, resource: resource, scope: permission_to_scope(%{domain: domain, resource: resource}), is_oauth_scope: false}
  end

  defp normalize_permission(scope) when is_binary(scope) do
    permission = scope_to_permission(scope)
    Map.put(permission, :scope, scope)
    |> Map.put(:is_oauth_scope, true)
  end

  # Core permission verification logic
  defp check_access?(permissions, "api", resource) do
    Enum.any?(permissions, fn perm ->
      case perm do
        # Direct API scope matches (OAuth scopes)
        %{scope: "api", is_oauth_scope: true} -> true
        %{scope: "api:read", is_oauth_scope: true} when resource in [nil, "read"] -> true
        %{scope: "api:write", is_oauth_scope: true} when resource in [nil, "read", "write"] -> true

        # Legacy domain/resource format (KeyPermissions)
        %{domain: "api", resource: nil, is_oauth_scope: false} -> true
        %{domain: "api", resource: "read", is_oauth_scope: false} when resource in [nil, "read"] -> true
        %{domain: "api", resource: "write", is_oauth_scope: false} when resource in [nil, "read", "write"] -> true

        # Package permission implies api:read (both OAuth and KeyPermission)
        %{domain: "package", is_oauth_scope: false} when resource in [nil, "read"] -> true
        %{scope: "package", is_oauth_scope: true} when resource in [nil, "read"] -> true

        _ -> false
      end
    end)
  end

  defp check_access?(permissions, "package", resource) do
    Enum.any?(permissions, fn perm ->
      case perm do
        # OAuth scope-based matching - these are true OAuth scopes
        %{scope: "api", is_oauth_scope: true} -> true
        %{scope: "api:write", is_oauth_scope: true} -> true
        %{scope: "package", is_oauth_scope: true} -> true

        # Legacy KeyPermission matching with specific package resource
        # Only allow when we have an actual Package struct to verify against
        %{domain: "package", resource: package_resource, is_oauth_scope: false} when is_binary(package_resource) ->
          case resource do
            %Package{} = pkg -> match_package_resource?(package_resource, pkg)
            _ -> false
          end

        %{domain: "package", resource: nil, is_oauth_scope: false} -> true

        _ -> false
      end
    end)
  end

  defp check_access?(permissions, "repositories", nil) do
    Enum.any?(permissions, fn perm ->
      case perm do
        %{scope: "repositories"} -> true
        %{domain: "repositories"} -> true
        _ -> false
      end
    end)
  end

  defp check_access?(permissions, "repository", resource) when is_binary(resource) do
    Enum.any?(permissions, fn perm ->
      case perm do
        %{scope: "repositories"} -> true
        %{domain: "repositories"} -> true
        %{domain: "repository", resource: ^resource} -> true
        _ -> false
      end
    end)
  end

  defp check_access?(permissions, "docs", resource) when is_binary(resource) do
    Enum.any?(permissions, fn perm ->
      case perm do
        %{domain: "docs", resource: ^resource} -> true
        _ -> false
      end
    end)
  end

  defp check_access?(_permissions, _domain, _resource), do: false

  # Helper functions for resource matching
  defp match_package_resource?(permission_resource, %Package{} = resource) do
    [organization, package] = String.split(permission_resource, "/")
    resource.repository.name == organization and resource.name == package
  end

  defp match_package_resource?(_permission_resource, _resource), do: false

  @doc """
  Verifies if a user or organization has access to a specific domain and resource.

  This checks user-level permissions (e.g., package ownership, repository access)
  rather than API key/token permissions. Used for validating that authenticated
  users can actually access the resources they're trying to modify.
  """
  def verify_user_access(%User{} = user, domain, resource) do
    User.verify_permissions(user, domain, resource)
  end

  def verify_user_access(%Organization{} = organization, domain, resource) do
    Organization.verify_permissions(organization, domain, resource)
  end
end
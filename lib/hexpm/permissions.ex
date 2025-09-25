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
  @simple_scopes ~w(repositories)
  @resource_only_scopes ~w(package repository docs)
  @all_scopes @api_scopes ++ @simple_scopes

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
  Supports both simple scopes and resource-specific scopes (e.g., package:decimal).
  """
  def validate_scopes(scopes) when is_list(scopes) do
    invalid_scopes = Enum.reject(scopes, &valid_scope?/1)

    case invalid_scopes do
      [] -> :ok
      _ -> {:error, "contains invalid scopes: #{Enum.join(invalid_scopes, ", ")}"}
    end
  end

  defp valid_scope?(scope) do
    case String.split(scope, ":", parts: 2) do
      [scope_name] ->
        scope_name in @all_scopes

      [scope_name, _resource] when scope_name in @resource_only_scopes ->
        # Allow resource-specific scopes for package, repository, and docs
        true

      ["api", sub] when sub in ["read", "write"] ->
        true

      _ ->
        false
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
  - %{domain: "package", resource: "hexpm/poison"} -> "package:hexpm/poison"
  - %{domain: "repository", resource: "acme"} -> "repository:acme"
  """
  def permission_to_scope(%{domain: domain, resource: resource}) do
    case {domain, resource} do
      {"api", nil} ->
        "api"

      {"api", resource} when resource in ["read", "write"] ->
        "#{domain}:#{resource}"

      {domain, nil} ->
        domain

      {domain, resource} when domain in ["package", "repository"] and is_binary(resource) ->
        "#{domain}:#{resource}"

      {domain, _} ->
        domain
    end
  end

  @doc """
  Converts a scope string to KeyPermission format.

  Examples:
  - "api:read" -> %{domain: "api", resource: "read"}
  - "api" -> %{domain: "api", resource: nil}
  - "package" -> %{domain: "package", resource: nil}
  - "package:hexpm/poison" -> %{domain: "package", resource: "hexpm/poison"}
  - "repository:acme" -> %{domain: "repository", resource: "acme"}
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
    %{
      domain: domain,
      resource: resource,
      scope: permission_to_scope(%{domain: domain, resource: resource}),
      is_oauth_scope: false
    }
  end

  defp normalize_permission(%{domain: domain, resource: resource}) do
    %{
      domain: domain,
      resource: resource,
      scope: permission_to_scope(%{domain: domain, resource: resource}),
      is_oauth_scope: false
    }
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
        %{scope: "api", is_oauth_scope: true} ->
          true

        %{scope: "api:read", is_oauth_scope: true} when resource in [nil, "read"] ->
          true

        %{scope: "api:write", is_oauth_scope: true} when resource in [nil, "read", "write"] ->
          true

        # Legacy domain/resource format (KeyPermissions)
        %{domain: "api", resource: nil, is_oauth_scope: false} ->
          true

        %{domain: "api", resource: "read", is_oauth_scope: false}
        when resource in [nil, "read"] ->
          true

        %{domain: "api", resource: "write", is_oauth_scope: false}
        when resource in [nil, "read", "write"] ->
          true

        # Package permission implies api:read (both OAuth and KeyPermission)
        %{domain: "package", is_oauth_scope: false} when resource in [nil, "read"] ->
          true

        %{scope: "package", is_oauth_scope: true} when resource in [nil, "read"] ->
          true

        _ ->
          false
      end
    end)
  end

  defp check_access?(permissions, "package", resource) do
    Enum.any?(permissions, fn perm ->
      case perm do
        # OAuth scope-based matching - these are true OAuth scopes
        %{scope: "api", is_oauth_scope: true} ->
          true

        %{scope: "api:write", is_oauth_scope: true} ->
          true

        # OAuth package scope with resource restriction
        %{scope: "package:" <> package_resource, is_oauth_scope: true}
        when is_binary(package_resource) ->
          case resource do
            %Package{} = pkg -> match_package_resource?(package_resource, pkg)
            _ -> false
          end

        # Legacy KeyPermission matching with specific package resource
        # Only allow when we have an actual Package struct to verify against
        %{domain: "package", resource: package_resource, is_oauth_scope: false}
        when is_binary(package_resource) ->
          case resource do
            %Package{} = pkg -> match_package_resource?(package_resource, pkg)
            _ -> false
          end

        %{domain: "package", resource: nil, is_oauth_scope: false} ->
          true

        _ ->
          false
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
        # OAuth repository scope with resource restriction
        %{scope: "repository:" <> repo_resource, is_oauth_scope: true} ->
          repo_resource == resource

        # OAuth repositories scope (grants access to all repositories)
        %{scope: "repositories"} ->
          true

        # Legacy domain-based permissions
        %{domain: "repositories"} ->
          true

        %{domain: "repository", resource: ^resource} ->
          true

        _ ->
          false
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

  @doc """
  Validates that target scopes are a subset of source scopes.
  Used for token exchange to ensure derived tokens have equal or reduced privileges.
  """
  def validate_scope_subset(source_scopes, target_scopes) do
    case scope_subset?(source_scopes, target_scopes) do
      true -> :ok
      false -> {:error, "target scopes must be subset of source scopes"}
    end
  end

  @doc """
  Checks if target scopes are completely contained in source scopes.
  """
  def scope_subset?(source_scopes, target_scopes) do
    Enum.all?(target_scopes, fn target_scope ->
      Enum.any?(source_scopes, &scope_contains?(&1, target_scope))
    end)
  end

  @doc """
  Checks if a source scope grants access to a target scope.
  Handles scope hierarchy: "api" contains "api:read"/"api:write", "api:write" contains "api:read".
  """
  def scope_contains?(source, target) do
    case {source, target} do
      # Same scope
      {same, same} -> true
      # api contains api:read and api:write
      {"api", "api:" <> _} -> true
      # api:write contains api:read
      {"api:write", "api:read"} -> true
      # repositories contains any repository:resource scope
      {"repositories", "repository:" <> _} -> true
      _ -> false
    end
  end

  @doc """
  Groups scopes by their category for organized display.
  Returns a map with categories as keys and lists of scopes as values.
  """
  def group_scopes(scopes) when is_list(scopes) do
    Enum.group_by(scopes, &scope_category/1)
  end

  @doc """
  Returns the category of a scope for grouping purposes.
  """
  def scope_category(scope) when is_binary(scope) do
    case String.split(scope, ":", parts: 2) do
      ["api" | _] -> :api
      ["package" | _] -> :package
      ["repository" | _] -> :repository
      ["repositories"] -> :repository
      ["docs" | _] -> :docs
      _ -> :other
    end
  end

  @doc """
  Formats a permission summary as human-readable text.
  """
  def format_summary(scopes) when is_list(scopes) do
    summary = summarize_permissions(scopes)

    parts = []

    parts =
      case summary.api_level do
        :full -> ["Full API access" | parts]
        :write -> ["Read/write API access" | parts]
        :read -> ["Read-only API access" | parts]
        _ -> parts
      end

    parts =
      if summary.all_repositories do
        ["Access to all repositories" | parts]
      else
        if summary.specific_repositories > 0 do
          ["Access to #{summary.specific_repositories} specific repository(ies)" | parts]
        else
          parts
        end
      end

    parts =
      if summary.specific_packages > 0 do
        ["Manage #{summary.specific_packages} specific package(s)" | parts]
      else
        parts
      end

    case parts do
      [] -> "No permissions granted"
      [single] -> single
      _ -> Enum.join(parts, ", ")
    end
  end

  defp summarize_permissions(scopes) do
    has_full_api = "api" in scopes
    has_write = "api:write" in scopes or has_full_api
    has_read = "api:read" in scopes or has_write

    package_scopes = Enum.filter(scopes, &String.starts_with?(&1, "package:"))
    repo_scopes = Enum.filter(scopes, &String.starts_with?(&1, "repository:"))
    has_all_repos = "repositories" in scopes

    %{
      api_level:
        cond do
          has_full_api -> :full
          has_write -> :write
          has_read -> :read
          true -> :none
        end,
      specific_packages: length(package_scopes),
      specific_repositories: length(repo_scopes),
      all_repositories: has_all_repos,
      total_scopes: length(scopes)
    }
  end

  @doc """
  Checks if the given scopes require write access (api or api:write).
  Used to determine if 2FA should be required for OAuth authorization.
  """
  def requires_write_access?(scopes) when is_list(scopes) do
    Enum.any?(scopes, fn scope ->
      scope == "api" || scope == "api:write"
    end)
  end

  def requires_write_access?(_), do: false

  @doc """
  Returns a human-readable description for OAuth scopes.

  Supports all scope types including resource-specific scopes.
  Raises an error for unknown scopes to ensure all scopes are properly documented.
  """
  def scope_description(scope) when is_binary(scope) do
    case scope do
      "api" ->
        "Complete access to your Hex account and packages"

      "api:read" ->
        "Read-only access to your Hex account and packages"

      "api:write" ->
        "Read and write access to your Hex account and packages"

      "repositories" ->
        "Access to all private repositories you have permission to"

      # Resource-specific scopes
      scope ->
        case String.split(scope, ":", parts: 2) do
          ["package", resource] ->
            "Manage the #{resource} package"

          ["repository", resource] ->
            "Access to the #{resource} private repository"

          ["docs", resource] ->
            "Fetch documentation for the #{resource} organization"

          _ ->
            raise ArgumentError, "Unknown scope: #{scope}. All scopes must have descriptions."
        end
    end
  end
end

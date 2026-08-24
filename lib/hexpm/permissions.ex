defmodule Hexpm.Permissions do
  @moduledoc """
  Unified permission system for API keys and OAuth tokens.

  This module provides a single source of truth for scope definitions and
  verification logic, consolidating the previously duplicated permission
  systems used by KeyPermission and OAuth tokens.
  """

  alias Hexpm.Accounts.{Key, KeyPermission, User, Users, Organization}
  alias Hexpm.Accounts.SSO.Enforcement
  alias Hexpm.OAuth.Token
  alias Hexpm.Repository.Package

  # Consolidated scope definitions - single source of truth
  @api_scopes ~w(api api:read api:write)
  @simple_scopes ~w(repositories)
  @resource_only_scopes ~w(package repository docs)
  @all_scopes @api_scopes ++ @simple_scopes

  # OAuth clients can register bare resource-only scopes as patterns
  @client_allowed_scopes @all_scopes ++ @resource_only_scopes

  # Legacy domain list for KeyPermission compatibility
  @legacy_domains ~w(api package repository repositories docs)

  # Scopes that name an organization, which both CDN edges verify from the token
  # without reading the database
  @organization_scope_domains ~w(repository docs)

  @doc """
  Returns all valid domains for KeyPermissions (legacy format).
  """
  def valid_domains, do: @legacy_domains

  @doc """
  Returns the list of resource-only scope prefixes (docs, package, repository).
  These scopes require a resource suffix (e.g., docs:acme, package:hexpm/poison).
  """
  def resource_only_scopes, do: @resource_only_scopes

  @doc """
  Checks if a scope is a resource-specific scope (e.g., docs:acme, package:hexpm/poison).
  """
  def resource_specific_scope?(scope) when is_binary(scope) do
    case String.split(scope, ":", parts: 2) do
      [base, _resource] when base in @resource_only_scopes -> true
      _ -> false
    end
  end

  @doc """
  Validates a scope for OAuth client registration.
  More permissive than user-requested scopes - allows bare resource-only scopes
  (docs, package, repository) as patterns that match any resource-specific scope.
  """
  def valid_client_allowed_scope?(scope) when is_binary(scope) do
    scope in @client_allowed_scopes or resource_specific_scope?(scope)
  end

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

  @doc """
  Expands the full API scope into the granular API scopes used for interactive
  authorization.
  """
  def expand_api_scope(scopes) when is_list(scopes) do
    scopes
    |> Enum.flat_map(fn
      "api" -> ["api:read", "api:write"]
      scope -> [scope]
    end)
    |> Enum.uniq()
  end

  defp valid_scope?(scope) do
    case String.split(scope, ":", parts: 2) do
      [scope_name] ->
        scope_name in @all_scopes

      ["api", sub] ->
        sub in ["read", "write"]

      ["package", resource] ->
        package_resource?(resource)

      [scope_name, resource] when scope_name in @resource_only_scopes ->
        resource != ""

      _ ->
        false
    end
  end

  # A package resource names one package in one organization.
  defp package_resource?(resource) do
    case String.split(resource, "/") do
      [organization, package] -> organization != "" and package != ""
      _other -> false
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
  Returns the list of OAuth scopes that a key permission grants access to.

  Unlike `permission_to_scope/1` which does a 1:1 mapping, this function
  returns all scopes the permission implies, respecting the scope hierarchy
  (e.g., write implies read).

  Examples:
  - %{domain: "api", resource: nil} -> ["api", "api:read", "api:write"]
  - %{domain: "api", resource: "write"} -> ["api:write", "api:read"]
  - %{domain: "api", resource: "read"} -> ["api:read"]
  - %{domain: "repository", resource: "acme"} -> ["repository:acme"]
  - %{domain: "repositories"} -> [:all_repositories]
  """
  def permission_to_scopes(%{domain: "api", resource: nil}),
    do: ["api", "api:read", "api:write"]

  def permission_to_scopes(%{domain: "api", resource: "write"}),
    do: ["api:write", "api:read"]

  def permission_to_scopes(%{domain: "api", resource: "read"}), do: ["api:read"]

  def permission_to_scopes(%{domain: "repository", resource: resource}),
    do: ["repository:#{resource}"]

  def permission_to_scopes(%{domain: "repositories"}), do: [:all_repositories]
  def permission_to_scopes(_permission), do: []

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
        # Legacy KeyPermission format
        %{domain: "docs", resource: ^resource} -> true
        # OAuth scope format: docs:{organization}
        %{scope: "docs:" <> scope_resource, is_oauth_scope: true} -> scope_resource == resource
        _ -> false
      end
    end)
  end

  defp check_access?(_permissions, _domain, _resource), do: false

  # Helper functions for resource matching
  defp match_package_resource?(permission_resource, %Package{} = resource) do
    case String.split(permission_resource, "/") do
      [organization, package] ->
        resource.repository.name == organization and resource.name == package

      _other ->
        false
    end
  end

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
  Expands the "repositories" scope into individual "repository:{org}" scopes.

  This is used for access tokens to create a capability-based token that explicitly
  lists which repositories can be accessed at the edge without database lookups.

  If `api_key` is provided, the expansion is constrained by the API key's permissions.
  This ensures that the expanded scopes don't exceed what the API key is allowed to access.

  Refresh tokens keep the "repositories" scope as-is.

  ## Examples

      iex> user = %User{organizations: [%{name: "acme"}, %{name: "widgets"}]}
      iex> expand_repositories_scope(user, ["api:read", "repositories"])
      ["api:read", "repository:acme", "repository:widgets"]

      iex> expand_repositories_scope(user, ["api:read"])
      ["api:read"]
  """
  def expand_repositories_scope(user, scopes, api_key \\ nil)

  def expand_repositories_scope(%Organization{} = org, scopes, api_key) do
    if "repositories" in scopes do
      allowed_repos = get_allowed_repositories_from_key(api_key.permissions)

      repo_scopes =
        if :all in allowed_repos or org.name in allowed_repos do
          ["repository:#{org.name}"]
        else
          []
        end

      scopes
      |> Enum.reject(&(&1 == "repositories"))
      |> Kernel.++(repo_scopes)
    else
      scopes
    end
  end

  def expand_repositories_scope(%User{} = user, scopes, nil) do
    if "repositories" in scopes do
      # Ensure organizations are preloaded
      user = Hexpm.Repo.preload(user, :organizations)

      # Get all organizations the user has access to
      organizations = Users.all_organizations(user)

      # Create individual repository scopes
      repo_scopes = Enum.map(organizations, fn org -> "repository:#{org.name}" end)

      # Replace "repositories" with individual scopes
      scopes
      |> Enum.reject(&(&1 == "repositories"))
      |> Kernel.++(repo_scopes)
    else
      scopes
    end
  end

  def expand_repositories_scope(%User{} = user, scopes, api_key) do
    if "repositories" in scopes do
      # Ensure organizations are preloaded
      user = Hexpm.Repo.preload(user, :organizations)

      # Get all organizations the user has access to
      organizations = Users.all_organizations(user)

      # Filter organizations based on API key permissions
      allowed_repos = get_allowed_repositories_from_key(api_key.permissions)

      repo_scopes =
        organizations
        |> Enum.map(fn org -> org.name end)
        |> Enum.filter(fn org_name ->
          # Allow if key has "repositories" permission or specific "repository:org_name" permission
          :all in allowed_repos or org_name in allowed_repos
        end)
        |> Enum.map(fn org_name -> "repository:#{org_name}" end)

      # Replace "repositories" with individual scopes
      scopes
      |> Enum.reject(&(&1 == "repositories"))
      |> Kernel.++(repo_scopes)
    else
      scopes
    end
  end

  defp filter_sso_scopes(%User{} = user, scopes, _user_session_id, %Key{}) do
    refused =
      user
      |> Enforcement.personal_key_refused()
      |> Enum.map(& &1.name)

    {Enum.reject(scopes, &names_organization?(&1, refused)), []}
  end

  defp filter_sso_scopes(%User{} = user, scopes, user_session_id, _credential) do
    case Enforcement.sso_required(user, organization_scope_names(scopes), user_session_id) do
      [] -> {scopes, []}
      required -> {Enum.reject(scopes, &names_organization?(&1, required)), required}
    end
  end

  defp filter_sso_scopes(_principal, scopes, _user_session_id, _credential), do: {scopes, []}

  @doc """
  Drops the organization scopes this session is not currently authenticated for,
  and names the organizations that authenticating would give back.

  This is where enforcement reaches the credential path. A token's scopes are a
  capability the edge verifies without a database lookup, so the decision has to
  be taken when they are minted rather than when they are used, and they are
  minted on every grant including refresh.

  `repositories` is expanded first, which is the only order that decides
  anything: it names no organization, so enforcement can neither drop nor name
  one until it has been expanded into the scopes that do.

  Every organization scope is then held against current membership, the ones
  the expansion produced and the ones the client was granted by name alike. A
  removed member's organization is not in `all_organizations/1`, so it goes
  without ever being named, while a member whose only missing piece is a live
  organization access session is dropped and named. A client can act on the
  second and has nothing to act on for the first.

  A token exchanged from a personal API key is the exception: it holds the
  key's standing rather than a session's, because it is minted with no refresh
  token and its session dies with it, so there is never an organization access
  session for it to carry. It keeps the organizations that accept personal keys
  and loses the ones that do not, and names neither, since a browser visit does
  not change what a static credential may reach.
  """
  @spec expand_and_filter_sso_scopes(term(), [String.t()], integer() | nil, Key.t() | nil) ::
          {[String.t()], [String.t()]}
  def expand_and_filter_sso_scopes(principal, scopes, user_session_id, credential \\ nil) do
    expanded =
      principal
      |> expand_repositories_scope(scopes)
      |> reject_unaffiliated_scopes(principal)

    filter_sso_scopes(principal, expanded, user_session_id, credential)
  end

  defp organization_scope_names(scopes) do
    scopes
    |> Enum.flat_map(fn scope ->
      case organization_scope_name(scope) do
        nil -> []
        name -> [name]
      end
    end)
    |> Enum.uniq()
  end

  defp names_organization?(scope, names), do: organization_scope_name(scope) in names

  defp get_allowed_repositories_from_key(permissions) do
    permissions
    |> Enum.flat_map(fn permission ->
      case permission.domain do
        "repositories" -> [:all]
        "repository" -> [permission.resource]
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  @doc """
  Drops organization scopes naming an organization the account is not in.

  `expand_repositories_scope/3` only rewrites the literal `repositories` scope,
  so an explicitly granted `repository:<org>` or `docs:<org>` passes through it
  untouched and `granted_scopes` carries it across every refresh. Both CDN edges
  verify these from the token without reading the database, so a scope kept here
  is access to that organization until the token expires.
  """
  def reject_unaffiliated_scopes(scopes, principal)

  def reject_unaffiliated_scopes(scopes, %User{} = user) do
    if Enum.any?(scopes, &organization_scope_name/1) do
      member_of =
        user
        |> Hexpm.Repo.preload(:organizations)
        |> Users.all_organizations()
        |> MapSet.new(& &1.name)

      Enum.reject(scopes, fn scope ->
        case organization_scope_name(scope) do
          nil -> false
          name -> not MapSet.member?(member_of, name)
        end
      end)
    else
      scopes
    end
  end

  def reject_unaffiliated_scopes(scopes, _principal), do: scopes

  defp organization_scope_name(scope) do
    case scope_to_permission(scope) do
      %{domain: domain, resource: name} when domain in @organization_scope_domains -> name
      _other -> nil
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
        "Complete access to your Hex account and packages. Includes: publish, unpublish, retire, and unretire packages; manage package owners; manage API keys."

      "api:read" ->
        "Read-only access to your Hex account and packages. Allows viewing packages, account information, organizations, and audit logs. Cannot modify any data."

      "api:write" ->
        "Write access to your Hex account and packages. Includes: publish, unpublish, retire, and unretire packages; manage package owners; manage API keys."

      "repositories" ->
        "Access to fetch packages from all private repositories you belong to. Does not grant ability to publish packages or modify repository settings."

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

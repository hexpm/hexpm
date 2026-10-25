defmodule Hexpm.Accounts.KeyGrantor do
  @moduledoc """
  Who creates a key, and so which permissions it may be given.

  A member grants what their organization role lets them do themselves, and a
  key or token grants what it holds.
  """

  alias Hexpm.Accounts.{Key, KeyPermission, Organization, Organizations, User}
  alias Hexpm.OAuth.Token
  alias Hexpm.Permissions

  defstruct [:owner, :principal, :credential, :role]

  @type t :: %__MODULE__{}

  @read_domains ~w(repository repositories docs)
  @write_capabilities ~w(publish keys)

  @doc """
  A grantor for a key owned by `owner`, created by `principal` authenticated
  with `credential`. The credential is nil for a browser session.
  """
  def new(owner, principal, credential) do
    %__MODULE__{
      owner: owner,
      principal: principal,
      credential: credential,
      role: member_role(owner, principal)
    }
  end

  defp member_role(%Organization{} = organization, %User{service: false} = user),
    do: Organizations.get_role(organization, user)

  defp member_role(_owner, _principal), do: nil

  @doc """
  Rewrites a request for `api` or `api:write`, or a request that names no
  permissions, into what this grantor may grant.

  A grantor that may grant the full API gets the literal permission. Anyone
  else gets the capabilities they may grant.
  """
  def request(%__MODULE__{} = grantor, params) do
    {key, permissions} = fetch_permissions(params)

    # An empty list leaves the embed unchanged, which would let the key's
    # unvalidated default stand, so it asks for the default like a missing one.
    permissions =
      case permissions do
        empty when empty in [nil, [], %{}] -> [%{"domain" => "api", "resource" => nil}]
        %{} = indexed -> indexed |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
        other -> other
      end

    if is_list(permissions) do
      Map.put(params, key, Enum.flat_map(permissions, &request_permission(grantor, &1)))
    else
      params
    end
  end

  defp fetch_permissions(params) do
    cond do
      Map.has_key?(params, :permissions) -> {:permissions, params.permissions}
      Map.has_key?(params, "permissions") -> {"permissions", params["permissions"]}
      Enum.any?(Map.keys(params), &is_atom/1) -> {:permissions, nil}
      true -> {"permissions", nil}
    end
  end

  defp request_permission(grantor, permission) when is_map(permission) do
    domain = permission["domain"] || permission[:domain]
    resource = permission["resource"] || permission[:resource]

    if domain == "api" and resource in [nil, "", "write"] and not full_api?(grantor) do
      case narrowed_api(grantor) do
        [] -> [permission]
        narrowed -> narrowed
      end
    else
      [permission]
    end
  end

  defp request_permission(_grantor, permission), do: [permission]

  defp narrowed_api(grantor) do
    candidates =
      case grantor.role do
        "read" -> ["api:read"]
        "write" -> ["api:read" | @write_capabilities]
        _other -> ["api:read" | Permissions.capability_domains()]
      end

    candidates
    |> Enum.map(&Permissions.scope_to_permission/1)
    |> Enum.filter(&grantable?(grantor, &1))
    |> Enum.map(&%{"domain" => &1.domain, "resource" => &1.resource})
  end

  @doc """
  Whether this grantor may grant `api` or `api:write` as is.
  """
  def full_api?(%__MODULE__{principal: %User{service: true}}), do: true

  def full_api?(%__MODULE__{} = grantor) do
    role_allows(grantor, %{domain: "api", resource: "write"}) == :ok and
      credential_full?(grantor.credential)
  end

  @doc """
  Whether this grantor may grant one permission.
  """
  def grantable?(grantor, permission), do: check(grantor, permission) == :ok

  @doc """
  `:ok`, or an error message naming the permission and why it can't be granted.
  """
  def check(%__MODULE__{} = grantor, permission) do
    if match?(%User{service: true}, grantor.principal) do
      :ok
    else
      with :ok <- role_allows(grantor, permission) do
        credential_holds(grantor.credential, permission)
      end
    end
  end

  # The dashboard and the API both look the member's role up when the key is
  # created.
  defp role_allows(
         %__MODULE__{owner: %Organization{} = organization, principal: %User{}} = grantor,
         permission
       ) do
    needed = required_role(permission)

    if grantor.role && grantor.role in Organization.role_or_higher(needed) do
      :ok
    else
      {:error, "#{scope(permission)} requires the #{needed} role in #{organization.name}"}
    end
  end

  defp role_allows(_grantor, _permission), do: :ok

  @doc """
  The lowest organization role that may grant a permission on an organization
  key.
  """
  def required_role(%{domain: "api", resource: "read"}), do: "read"
  def required_role(%{domain: domain}) when domain in @read_domains, do: "read"
  def required_role(%{domain: domain}) when domain in @write_capabilities, do: "write"
  def required_role(_permission), do: "admin"

  defp credential_holds(nil, _permission), do: :ok

  defp credential_holds(credential, permission) do
    if credential_full?(credential) or
         (holds?(held(credential), permission) and reads_held?(credential, permission)) or
         implied_read?(credential, permission) do
      :ok
    else
      {:error, "#{scope(permission)} is not held by the authenticating key"}
    end
  end

  # A key's package permission satisfies `api:read`, a token's package scope
  # doesn't, so a token passes one on to a key only when it holds the reads.
  defp reads_held?(%Token{} = token, %{domain: "package", resource: resource})
       when is_binary(resource),
       do: has?(held(token), "api", "read") or has?(held(token), "package", nil)

  defp reads_held?(_credential, _permission), do: true

  # A key's package permission and a token's bare package scope both answer
  # `api:read`, so they can pass it on.
  defp implied_read?(%Key{permissions: permissions}, %{domain: "api", resource: "read"}),
    do: Enum.any?(permissions, &(&1.domain == "package"))

  defp implied_read?(%Token{} = token, %{domain: "api", resource: "read"}),
    do: has?(held(token), "package", nil)

  defp implied_read?(_credential, _permission), do: false

  defp credential_full?(nil), do: true

  defp credential_full?(credential) do
    Enum.any?(held(credential), &(&1.domain == "api" and &1.resource in [nil, "write"]))
  end

  defp held(%Key{permissions: permissions}), do: permissions
  defp held(%Token{scopes: scopes}), do: Enum.map(scopes, &Permissions.scope_to_permission/1)

  defp holds?(held, %{domain: "repository", resource: resource}) do
    has?(held, "repositories", nil) or has?(held, "repository", resource)
  end

  defp holds?(held, %{domain: domain, resource: resource})
       when domain in ["publish", "owners"] and is_binary(resource) do
    has?(held, domain, nil) or has?(held, domain, resource) or has?(held, "package", nil) or
      has?(held, "package", resource)
  end

  # Every package permission also satisfies `api:read`, so building one out of
  # publish and owners permissions needs the reads as well.
  defp holds?(held, %{domain: "package", resource: resource}) when is_binary(resource) do
    has?(held, "package", nil) or has?(held, "package", resource) or
      (holds?(held, %{domain: "publish", resource: resource}) and
         holds?(held, %{domain: "owners", resource: resource}) and has?(held, "api", "read"))
  end

  defp holds?(held, %{domain: domain, resource: resource}), do: has?(held, domain, resource)

  defp has?(held, domain, resource),
    do: Enum.any?(held, &(&1.domain == domain and &1.resource == resource))

  defp scope(%KeyPermission{} = permission),
    do: Permissions.permission_to_scope(Map.from_struct(permission))

  defp scope(permission), do: Permissions.permission_to_scope(permission)
end

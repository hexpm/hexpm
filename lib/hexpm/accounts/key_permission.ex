defmodule Hexpm.Accounts.KeyPermission do
  use Hexpm.Schema

  alias Hexpm.Accounts.SSO.Enforcement
  alias Hexpm.Permissions

  @derive {HexpmWeb.Stale, last_modified: nil}

  embedded_schema do
    field :domain, :string
    field :resource, :string
  end

  def changeset(struct, user_or_organization, params) do
    cast(struct, params, ~w(domain resource)a)
    |> validate_inclusion(:domain, Permissions.valid_domains())
    |> normalize_resource()
    |> validate_resource()
    |> validate_permission(user_or_organization)
    |> validate_personal_key_reach(user_or_organization)
  end

  defp validate_resource(changeset) do
    validate_change(changeset, :resource, fn _, resource ->
      case get_change(changeset, :domain) do
        nil -> []
        "api" when resource in [nil, "read", "write"] -> []
        "repository" when is_binary(resource) -> []
        "package" when is_binary(resource) -> []
        "docs" when is_binary(resource) -> []
        "repositories" when is_nil(resource) -> []
        _ -> [resource: "invalid resource for given domain"]
      end
    end)
  end

  defp validate_permission(changeset, user_or_organization) do
    # Earlier validations (validate_inclusion on :domain, validate_resource)
    # ensure the (domain, resource) pair is well-formed before we hand it to
    # verify_user_access, which only accepts the supported combinations. Bail
    # out early when the changeset is already invalid so the user sees the
    # original validation error instead of a 500.
    if changeset.valid? do
      validate_change(changeset, :resource, fn _, resource ->
        domain = get_change(changeset, :domain)

        case Permissions.verify_user_access(user_or_organization, domain, resource) do
          {:ok, _} ->
            []

          :error when domain in ["repository", "docs"] ->
            [resource: "you do not have access to this repository"]

          :error when domain == "package" ->
            [resource: "you do not have access to this package"]
        end
      end)
    else
      changeset
    end
  end

  # The key has nowhere to hang an organization access session, so refusing it
  # here rather than at the request means the member finds out while they are
  # still on the form and can pick a credential that works.
  defp validate_personal_key_reach(changeset, user_or_organization) do
    with true <- changeset.valid?,
         reach when not is_nil(reach) <- organization_reach(apply_changes(changeset)),
         organization when not is_nil(organization) <-
           Enum.find(Enforcement.personal_key_refused(user_or_organization), &reached?(&1, reach)) do
      add_error(changeset, :resource, Enforcement.refusal_message(:personal_key, organization))
    else
      _ -> changeset
    end
  end

  @doc """
  The organization this permission names, `:every` for one that names them all,
  or nil for one that names none.

  An `api` permission names no organization, so nothing can be stripped from it
  and the request that uses it is refused where it is authorized instead. A
  package resource is stored as `organization/package`, the organization having
  been put on when it was cast, so one without a slash names a package rather
  than an organization.
  """
  def organization_reach(%__MODULE__{domain: domain, resource: name})
      when domain in ["repository", "docs"] and is_binary(name),
      do: name

  def organization_reach(%__MODULE__{domain: "repositories"}), do: :every

  def organization_reach(%__MODULE__{domain: "package", resource: resource})
      when is_binary(resource) do
    case String.split(resource, "/", parts: 2) do
      [organization, _package] -> organization
      [_package] -> nil
    end
  end

  def organization_reach(%__MODULE__{}), do: nil

  defp reached?(_organization, :every), do: true
  defp reached?(organization, name), do: organization.name == name

  defp normalize_resource(changeset) do
    update_change(changeset, :resource, fn resource ->
      case get_change(changeset, :domain) do
        "package" ->
          if String.contains?(resource, "/") do
            resource
          else
            "hexpm/#{resource}"
          end

        _other ->
          resource
      end
    end)
  end
end

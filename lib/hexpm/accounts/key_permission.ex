defmodule Hexpm.Accounts.KeyPermission do
  use Hexpm.Schema

  alias Hexpm.Permissions

  @derive HexpmWeb.Stale

  embedded_schema do
    field :domain, :string
    field :resource, :string
  end

  def changeset(struct, user_or_organization, params) do
    cast(struct, params, ~w(domain resource)a)
    |> validate_inclusion(:domain, Permissions.valid_domains())
    |> validate_user_key_domain(user_or_organization)
    |> normalize_resource()
    |> validate_resource()
    |> validate_permission(user_or_organization)
  end

  defp validate_user_key_domain(changeset, %User{}) do
    validate_change(changeset, :domain, fn _, domain ->
      if domain in ["repository", "repositories"] do
        [
          domain:
            "user keys cannot have repository permissions, generate an organization key instead"
        ]
      else
        []
      end
    end)
  end

  defp validate_user_key_domain(changeset, _user_or_organization), do: changeset

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

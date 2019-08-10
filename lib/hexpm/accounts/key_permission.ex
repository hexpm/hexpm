defmodule Hexpm.Accounts.KeyPermission do
  use Hexpm.Schema

  @derive HexpmWeb.Stale
  @domains ~w(api repository repositories docs)

  embedded_schema do
    field :domain, :string
    field :resource, :string
  end

  def changeset(struct, user_or_organization, params) do
    cast(struct, params, ~w(domain resource)a)
    |> validate_inclusion(:domain, @domains)
    |> validate_resource()
    |> validate_permission(user_or_organization)
  end

  defp validate_permission(changeset, user_or_organization) do
    validate_change(changeset, :resource, fn _, resource ->
      domain = get_change(changeset, :domain)

      case verify_permissions(user_or_organization, domain, resource) do
        {:ok, _} ->
          []

        :error ->
          # NOTE: Possibly change repository if we add more domains
          [resource: "you do not have access to this repository"]
      end
    end)
  end

  defp validate_resource(changeset) do
    validate_change(changeset, :resource, fn _, resource ->
      case get_change(changeset, :domain) do
        nil -> []
        "api" when resource in [nil, "read", "write"] -> []
        "repository" when is_binary(resource) -> []
        "docs" when is_binary(resource) -> []
        "repositories" when is_nil(resource) -> []
        _ -> [resource: "invalid resource for given domain"]
      end
    end)
  end

  def verify_permissions(%User{} = user, domain, resource),
    do: User.verify_permissions(user, domain, resource)

  def verify_permissions(%Organization{} = organization, domain, resource),
    do: Organization.verify_permissions(organization, domain, resource)
end

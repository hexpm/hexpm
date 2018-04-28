defmodule Hexpm.Accounts.KeyPermission do
  use Hexpm.Web, :schema

  @derive Hexpm.Web.Stale
  @domains ~w(api repository repositories)

  embedded_schema do
    field :domain, :string
    field :resource, :string
  end

  def changeset(struct, user, params) do
    cast(struct, params, ~w(domain resource)a)
    |> validate_inclusion(:domain, @domains)
    |> validate_resource()
    |> validate_permission(user)
  end

  defp validate_permission(changeset, user) do
    validate_change(changeset, :resource, fn _, resource ->
      domain = get_change(changeset, :domain)

      case User.verify_permissions(user, domain, resource) do
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
        "repositories" when is_nil(resource) -> []
        true -> [resource: "invalid resource for given domain"]
      end
    end)
  end
end

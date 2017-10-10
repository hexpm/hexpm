defmodule Hexpm.Accounts.KeyPermission do
  use Hexpm.Web, :schema

  @derive Hexpm.Web.Stale
  @domains ~w(api repository)

  embedded_schema do
    field :domain, :string
    field :resource, :string
  end

  def changeset(struct, user, params) do
    cast(struct, params, ~w(domain resource))
    |> validate_inclusion(:domain, @domains)
    |> validate_required_resource()
    |> validate_permission(user)
  end

  defp validate_required_resource(changeset) do
    if get_change(changeset, :domain) == "repository" do
      validate_required(changeset, :resource)
    else
      changeset
    end
  end

  defp validate_permission(changeset, user) do
    validate_change(changeset, :resource, fn _, resource ->
      domain = get_change(changeset, :domain)
      if User.verify_permissions?(user, domain, resource) do
        []
      else
        # NOTE: Possibly change repository if we add more domains
        [resource: "you do not have access to this repository"]
      end
    end)
  end
end

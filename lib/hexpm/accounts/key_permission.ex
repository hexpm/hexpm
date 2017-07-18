defmodule Hexpm.Accounts.KeyPermission do
  use Hexpm.Web, :schema

  embedded_schema do
    field :domain, :string
    field :resource, :string
  end

  @domains ~w(api repository)

  def changeset(struct, params) do
    cast(struct, params, ~w(domain resource))
    |> validate_inclusion(:domain, @domains)
    |> validate_required_resource()
  end

  defp validate_required_resource(changeset) do
    if get_change(changeset, :domain) == "repository" do
      validate_required(changeset, :resource)
    else
      changeset
    end
  end
end

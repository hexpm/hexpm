defmodule Hexpm.Repository.ReleaseMetadata do
  use Hexpm.Web, :schema

  @derive Hexpm.Web.Stale

  embedded_schema do
    field :app, :string
    field :build_tools, {:array, :string}
    field :elixir, :string
  end

  def changeset(meta, params) do
    cast(meta, params, ~w(app build_tools elixir))
    |> validate_required(~w(app build_tools)a)
    |> validate_list_required(:build_tools)
    |> update_change(:build_tools, &Enum.uniq/1)
    |> validate_requirement(:elixir, pre: true)
  end
end

defmodule Hexpm.Repository.ReleaseMetadata do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  embedded_schema do
    field :app, :string
    field :build_tools, {:array, :string}
    field :elixir, :string
    field :files, {:array, :string}, virtual: true
  end

  def changeset(meta, params) do
    cast(meta, params, ~w(app build_tools elixir files)a)
    |> validate_required(~w(app build_tools files)a)
    |> validate_list_required(:build_tools)
    |> validate_list_required(:files, message: "package can't be empty")
    |> update_change(:build_tools, &Enum.uniq/1)
    |> validate_requirement(:elixir)
  end
end

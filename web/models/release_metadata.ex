defmodule HexWeb.ReleaseMetadata do
  use HexWeb.Web, :model

  embedded_schema do
    field :app, :string
    field :build_tools, {:array, :string}
    field :elixir, :string
  end

  @required_fields ~w(app)
  @optional_fields ~w(build_tools elixir)

  def changeset(meta, params \\ :empty) do
    cast(meta, params, @required_fields, @optional_fields)
  end
end

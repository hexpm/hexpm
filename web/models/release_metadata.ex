defmodule HexWeb.ReleaseMetadata do
  use HexWeb.Web, :model

  embedded_schema do
    field :app, :string
    field :build_tools, {:array, :string}
    field :elixir, :string
  end

  def changeset(meta, params \\ %{}) do
    cast(meta, params, ~w(app build_tools elixir))
    |> validate_required(:app)
  end
end

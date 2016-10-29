defmodule HexWeb.ReleaseMetadata do
  use HexWeb.Web, :model

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
    |> validate_elixir()
  end

  defp validate_elixir(changeset) do
    validate_change(changeset, :elixir, fn _, elixir ->
      case Version.parse_requirement(elixir) do
        {:ok, _} -> []
        _ -> [elixir: "has invalid version requirement"]
      end
    end)
  end
end

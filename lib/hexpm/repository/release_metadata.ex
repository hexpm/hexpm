defmodule Hexpm.Repository.ReleaseMetadata do
  use Hexpm.Schema

  @derive {HexpmWeb.Stale, last_modified: nil}

  embedded_schema do
    field :app, :string
    field :build_tools, {:array, :string}
    field :elixir, :string
    field :files, {:array, :string}, virtual: true
  end

  def changeset(meta, params) do
    cast(meta, params, ~w(app build_tools elixir files)a)
    |> validate_required(~w(app build_tools files)a)
    |> validate_length(:app, count: :codepoints, max: 255)
    |> validate_length(:build_tools, max: 16)
    |> validate_each_length(:build_tools, count: :codepoints, max: 255)
    |> validate_length(:elixir, count: :bytes, max: 255)
    |> validate_list_required(:build_tools)
    |> validate_list_required(:files, message: "package can't be empty")
    |> update_change(:build_tools, &Enum.uniq/1)
    |> validate_requirement(:elixir)
  end
end

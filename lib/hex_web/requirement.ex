defmodule HexWeb.Requirement do
  use Ecto.Model

  schema "requirements" do
    field :app, :string
    field :requirement, :string
    field :optional, :boolean

    belongs_to :release, HexWeb.Release
    belongs_to :dependency, HexWeb.Package
  end
end

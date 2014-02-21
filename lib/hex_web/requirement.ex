defmodule HexWeb.Requirement do
  use Ecto.Model

  queryable "requirements" do
    belongs_to :release, HexWeb.Release
    belongs_to :dependency, HexWeb.Package
    field :requirement, :string
  end
end

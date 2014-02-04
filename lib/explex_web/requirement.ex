defmodule ExplexWeb.Requirement do
  use Ecto.Model

  queryable "requirements" do
    belongs_to :release, ExplexWeb.Release
    belongs_to :dependency, ExplexWeb.Package
    field :requirement, :string
  end
end

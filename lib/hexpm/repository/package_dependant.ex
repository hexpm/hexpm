defmodule Hexpm.Repository.PackageDependant do
  use Hexpm.Schema

  schema "package_dependants" do
    belongs_to :package, Package, foreign_key: :dependant_id
    field :name, :string
    field :repo, :string
  end
end

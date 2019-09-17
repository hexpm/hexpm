defmodule Hexpm.Repository.PackageDependant do
  use Hexpm.Schema

  schema "package_dependants" do
    belongs_to :package, Package
    field :name, :string
    field :repo, :string
  end
end

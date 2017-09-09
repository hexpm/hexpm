defmodule Hexpm.Repository.PackageDependant do
  use Hexpm.Web, :schema

  schema "package_dependants" do
    belongs_to :package, Package
    field :name, :string
  end
end

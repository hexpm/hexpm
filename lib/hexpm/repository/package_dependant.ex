defmodule Hexpm.Repository.PackageDependant do
  use HexpmWeb, :schema

  schema "package_dependants" do
    belongs_to :package, Package
    field :name, :string
  end
end

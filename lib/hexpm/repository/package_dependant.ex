defmodule Hexpm.Repository.PackageDependant do
  use Hexpm.Schema

  schema "package_dependants" do
    belongs_to :dependency, Package
    belongs_to :package, Package
    belongs_to :dependant_repository, Repository
  end
end

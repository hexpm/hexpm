defmodule Hexpm.Repository.PackageOwner do
  use Hexpm.Web, :schema

  schema "package_owners" do
    belongs_to :package, Package
    belongs_to :owner, User
  end
end

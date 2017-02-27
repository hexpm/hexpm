defmodule HexWeb.PackageOwner do
  use HexWeb.Web, :schema

  schema "package_owners" do
    belongs_to :package, Package
    belongs_to :owner, User
  end
end

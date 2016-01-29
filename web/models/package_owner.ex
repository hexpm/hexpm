defmodule HexWeb.PackageOwner do
  use HexWeb.Web, :model

  schema "package_owners" do
    belongs_to :package, Package
    belongs_to :owner, User
  end
end

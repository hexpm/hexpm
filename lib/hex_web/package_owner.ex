defmodule HexWeb.PackageOwner do
  use Ecto.Model

  schema "package_owners" do
    belongs_to :package, HexWeb.Package
    belongs_to :owner, HexWeb.User
  end
end

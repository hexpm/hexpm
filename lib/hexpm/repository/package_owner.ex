defmodule Hexpm.Repository.PackageOwner do
  use HexpmWeb, :schema

  schema "package_owners" do
    field :level, :string, default: "full"

    belongs_to :package, Package
    belongs_to :user, User

    timestamps()
  end

  @valid_levels ["full", "maintainer"]

  def changeset(package_owner, params) do
    cast(package_owner, params, [:level])
    |> unique_constraint(:user_id, name: "package_owners_unique", message: "is already owner")
    |> validate_required(:level)
    |> validate_inclusion(:level, @valid_levels)
  end
end

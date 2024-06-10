defmodule Hexpm.Repository.PackageSearches.PackageSearch do
  @moduledoc """
  This module handles data related to package searches for the purpose
  of identifying common misspellings, searches for non-existent
  packages, etc.
  """

  use Hexpm.Schema

  schema "package_searches" do
    belongs_to :package, Package

    field :term, :string
    field :frequency, :integer, default: 1

    timestamps()
  end

  def changeset(package_search, params) do
    package_search
    |> cast(params, [:term, :frequency, :package_id])
    |> validate_required([:term])
    |> unique_constraint(:term)
  end
end

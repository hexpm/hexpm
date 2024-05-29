defmodule Hexpm.Repository.PackageSearch do
  @moduledoc """
  This module handles data related to package searches for the purpose
  of identifying common misspellings, searches for non-existent
  packages, etc.
  """

  use Hexpm.Schema

  schema "package_search" do
    belongs_to :package, Package
    field :term, :string
    field :frequency, :integer, default: 0
  end

end

defmodule HexWeb.Validation do
  @moduledoc """
  Ecto validation helpers.
  """

  import Ecto.Changeset

  @doc """
  Checks if a version is valid semver.
  """
  def validate_version(changeset, field) do
    validate_change(changeset, field, fn
      _, %Version{build: nil} ->
        []
      _, %Version{} ->
        [{field, :build_number_not_allowed}]
    end)
  end
end

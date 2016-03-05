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

  @doc """
  Adds embed errors to the changeset.errors
  """
  def put_embed_errors(%Ecto.Changeset{changes: changes} = changeset, embed) do
    if changes[embed] && length(changes[embed].errors) > 0 do
      %{changeset | errors: changeset.errors ++ [{embed, changes[embed].errors}]}
    else
      changeset
    end
  end
end

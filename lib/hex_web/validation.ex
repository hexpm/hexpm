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
  Adds embed errors directly to the `changeset.errors`. This way we don't need to
  extract them through `Ecto.Chanegset.traverse_errors/2`.
  """
  def put_embed_errors(%Ecto.Changeset{changes: changes} = changeset, embed) do
    if changes[embed] && changes[embed].errors != [] do
      %{changeset | errors: changeset.errors ++ [{embed, changes[embed].errors}]}
    else
      changeset
    end
  end
end

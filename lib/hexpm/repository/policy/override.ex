defmodule Hexpm.Repository.Policy.Override do
  @moduledoc """
  A per-package final say within a repository tab. An `allow` override permits
  every matching release and bypasses the tab's restriction; a `deny` override
  blocks every matching release. The optional `requirement` narrows the
  override to releases that satisfy it; an override without one applies to the
  whole package.
  """
  use Hexpm.Schema

  @valid_actions ~w(allow deny)
  @package_format ~r/^[a-z0-9][a-z0-9_\-\.]*[a-z0-9]$/

  embedded_schema do
    field :action, Ecto.Enum, values: [:allow, :deny]
    field :package, :string
    field :requirement, :string
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [:action, :package, :requirement])
    |> update_change(:requirement, &nilify_blank/1)
    |> validate_required([:action, :package])
    |> validate_inclusion(:action, @valid_actions)
    |> validate_format(:package, @package_format)
    |> validate_requirement()
  end

  defp validate_requirement(changeset) do
    case get_change(changeset, :requirement) do
      nil ->
        changeset

      requirement ->
        case Version.parse_requirement(requirement) do
          {:ok, _} -> changeset
          :error -> add_error(changeset, :requirement, "is invalid")
        end
    end
  end

  defp nilify_blank(nil), do: nil

  defp nilify_blank(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

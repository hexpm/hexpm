defmodule HexWeb.PackageMetadata do
  use HexWeb.Web, :model

  embedded_schema do
    # TODO: contributors is depracated, use maintainers
    field :contributors, {:array, :string}
    field :description, :string
    field :licenses, {:array, :string}
    field :links, :map
    field :maintainers, {:array, :string}
  end

  @required_fields ~w(description)
  @optional_fields ~w(contributors licenses links maintainers)

  def changeset(meta, params \\ :empty) do
    cast(meta, params, @required_fields, @optional_fields)
    |> validate_presence(:description)
  end

  # TODO: replace with `validate_required` in Ecto 2.0.0
  defp validate_presence(changeset, field) do
    validate_change changeset, field, fn _, value ->
      is_present = (value |> String.strip |> String.length) > 0
      if is_present, do: [], else: [{field, "can't be blank"}]
    end
  end
end

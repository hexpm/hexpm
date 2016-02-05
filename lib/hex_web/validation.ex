defmodule HexWeb.Validation do
  @doc """
  Ecto validation helpers.
  """

  import Ecto.Changeset

  def type(_field, nil, _type) do
    []
  end

  def type(field, value, {:dict, key_type, value_type}) when is_map(value) do
    errors = Enum.flat_map(value, fn {key, _} -> type(field, key, key_type) end) ++
             Enum.flat_map(value, fn {_, value} -> type(field, value, value_type) end)
    if errors == [] do
      []
    else
      [{field, "expected type dict(#{key_type}, #{value_type})"}]
    end
  end

  def type(field, _value, {:dict, key_type, value_type}) do
    [{field, "expected type dict(#{key_type}, #{value_type})"}]
  end

  def type(_field, value, :string) when is_binary(value),
    do: []
  def type(field, _value, :string),
    do: [{field, "expected type string"}]

  def type(field, value, {:array, inner}) when is_list(value) do
    errors = Enum.flat_map(value, &type(field, &1, inner))
    if errors == [] do
      []
    else
      [{field, "expected type array(#{inner})"}]
    end
  end

  def type(field, _value, {:array, inner}),
    do: [{field, "expected type array(#{inner})"}]

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

  def validate_meta(changeset, field, meta_types, meta_required) do
    validate_change(changeset, field, fn _field, meta ->
      type_errors =
        Enum.flat_map(meta_types, fn {sub_field, type} ->
          type(sub_field, Map.get(meta, sub_field), type)
        end)

      req_errors =
        Enum.flat_map(meta_required, fn field ->
          if Map.has_key?(meta, field) do
            []
          else
            [{field, :missing}]
          end
        end)

      errors = req_errors ++ type_errors

      if errors == [],
          do: [],
        else: [{field, errors}]
    end)
  end
end

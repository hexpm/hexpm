defmodule HexWeb.Validation do
  @doc """
  Ecto validation helpers.
  """

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

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

  @doc """
  Checks if the fields on the given entity are unique
  by querying the database.
  """
  def validate_unique(changeset, field, opts \\ []) do
    validate_change(changeset, field, fn _field, value ->
      model        = changeset.model
      module       = model.__struct__
      repo         = Keyword.fetch!(opts, :on)
      scope        = opts[:scope] || []

      query =
        from var in module,
             where: field(var, ^field) == ^value,
             limit: 1,
             select: true

      query =
        Enum.reduce(scope, query, fn field, query ->
          value = Map.fetch!(model, field)
          from var in query,
               where: field(var, ^field) == ^value
        end)

      if repo.all(query) == [true] do
        [{field, :already_taken}]
      else
        []
      end
    end)
  end
end

defmodule ExplexWeb.Validation do
  @doc """
  Ecto validation helpers.
  """

  alias Ecto.Query.Util
  require Ecto.Query

  @doc """
  Checks if a version is valid semver.
  """
  def valid_version(attr, version, opts \\ []) do
    case Version.parse(version) do
      { :ok, _ } ->
        []
      :error ->
        [{ attr, opts[:message] || "invalid version: #{version}" }]
    end
  end

  @doc """
  Checks if the fields on the given entity are unique
  by querying the database.
  """
  def unique(entity, fields, opts \\ []) when is_list(opts) do
    model   = entity.model
    repo    = Keyword.fetch!(opts, :on)
    scope   = opts[:scope] || []
    message = opts[:message] || "already taken"

    where =
      Enum.reduce(fields, false, fn field, acc ->
        value = apply(entity, field, [])
        quote(do: unquote(acc) or &0.unquote(field) == unquote(value))
      end)

    where =
      Enum.reduce(scope, where, fn field, acc ->
        value = apply(entity, field, [])
        quote(do: unquote(acc) and &0.unquote(field) == unquote(value))
      end)

    select = Enum.map(fields, fn field -> quote(do: &0.unquote(field)) end)

    query = Ecto.Query.from(model, limit: 1)
                      .select(Ecto.Query.QueryExpr[expr: select])
                      .wheres([Ecto.Query.QueryExpr[expr: where]])

    case repo.all(query) do
      [values] ->
        zipped = Enum.zip(fields, values)
        Enum.flat_map(zipped, fn { field, value } ->
          if apply(entity, field, []) == value do
            [{ field, message }]
          else
            []
          end
        end)
      _ ->
        []
    end
  end

  @doc """
  Checks if the field value is of the specified type.

  Uses ecto types but is extended with `{ :dict, key, value }` for
  list dicts.
  """
  def type(attr, value, expected, opts \\ []) do
    if Util.type_castable_to?(expected) do
      value = Util.try_cast(value, expected)
    end

    case value_to_type(value) do
      { :ok, type } ->
        if Util.type_eq?(expected, type) do
          []
        else
          expected_str = type_to_ast(expected) |> Macro.to_string
          [{ attr, opts[:message] || "wrong type, expected: #{expected_str}" }]
        end

      { :error, _ } ->
        expected_str = type_to_ast(expected) |> Macro.to_string
        [{ attr, opts[:message] || "unknown type, expected: #{expected_str}" }]
    end
  end

  defp type_extension(dict) when is_list(dict) do
    try do
      { k_type, v_type } =
        Enum.reduce(dict, { :any, :any }, fn
          { k, v }, { k_expected, v_expected } ->
            case { value_to_type(k), value_to_type(v) } do
              { { :ok, k_type, }, { :ok, v_type } } ->
                if Util.type_eq?(k_type, k_expected) and Util.type_eq?(v_type, v_expected) do
                  { k_type, v_type }
                else
                  throw :error
                end
              _ ->
                throw :error
            end
          _, _ ->
            throw :error
        end)
      { :ok, { :dict, k_type, v_type } }

    catch
      :error -> { :error, "" }
    end
  end

  defp type_extension(_), do: { :error, "" }

  defp type_to_ast({ :dict, arg1, arg2 }) do
    { :dict, [], [type_to_ast(arg1), type_to_ast(arg2)] }
  end

  defp type_to_ast(arg), do: Util.type_to_ast(arg)

  defp value_to_type(nil), do: { :ok, :any }
  defp value_to_type(value), do: Util.value_to_type(value, &type_extension/1)
end

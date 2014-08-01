defmodule HexWeb.Validation do
  @doc """
  Ecto validation helpers.
  """

  alias Ecto.Query.Util
  require Ecto.Query

  @doc """
  Checks if a version is valid semver.
  """
  def valid_version(attr, version, opts \\ []) do
    allow_pre = Keyword.get(opts, :pre, true)

    case Version.parse(version) do
      {:ok, %Version{pre: pre}} when allow_pre or pre == [] ->
        []
      {:ok, %Version{}} when not allow_pre ->
        [{attr, opts[:message] || "pre release version is not allowed"}]
      _ ->
        [{attr, opts[:message] || "invalid version"}]
    end
  end

  @doc """
  Checks if the fields on the given entity are unique
  by querying the database.
  """
  def unique(model, fields, opts \\ []) when is_list(opts) do
    module  = model.__struct__
    repo    = Keyword.fetch!(opts, :on)
    scope   = opts[:scope] || []
    message = opts[:message] || "already taken"
    case    = Keyword.get(opts, :case_sensitive, true)

    where =
      Enum.reduce(fields, false, fn field, acc ->
        value = Map.fetch!(model, field)
        if case and is_binary(value) do
          quote(do: unquote(acc) or downcase(&0.unquote(field)) == downcase(unquote(value)))
        else
          quote(do: unquote(acc) or &0.unquote(field) == unquote(value))
        end
      end)

    where =
      Enum.reduce(scope, where, fn field, acc ->
        value = Map.fetch!(model, field)
        quote(do: unquote(acc) and &0.unquote(field) == unquote(value))
      end)

    select = Enum.map(fields, fn field -> quote(do: &0.unquote(field)) end)

    query = %{Ecto.Query.from(module, limit: 1) |
                select: %Ecto.Query.QueryExpr{expr: select},
                wheres: [%Ecto.Query.QueryExpr{expr: where}]}

    case repo.all(query) do
      [values] ->
        zipped = Enum.zip(fields, values)
        Enum.flat_map(zipped, fn {field, value} ->
          if Map.fetch!(model, field) == value do
            [{field, message}]
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

  Uses ecto types but is extended with `{:dict, key, value}` for
  list dicts.
  """
  def type(attr, value, expected, opts \\ []) do
    value = Util.try_cast(value, expected)

    case value_to_type(value) do
      {:ok, type} ->
        if Util.type_eq?(expected, type) do
          []
        else
          expected_str = type_to_ast(expected) |> Macro.to_string
          [{attr, opts[:message] || "wrong type, expected: #{expected_str}"}]
        end

      {:error, _} ->
        expected_str = type_to_ast(expected) |> Macro.to_string
        [{attr, opts[:message] || "unknown type, expected: #{expected_str}"}]
    end
  end

  defp type_extension(dict) when is_map(dict) do
    try do
      {k_type, v_type} =
        Enum.reduce(dict, {:any, :any}, fn
          {k, v}, {k_expected, v_expected} ->
            case {value_to_type(k), value_to_type(v)} do
              {{:ok, k_type,}, {:ok, v_type}} ->
                if Util.type_eq?(k_type, k_expected) and Util.type_eq?(v_type, v_expected) do
                  {k_type, v_type}
                else
                  throw :error
                end
              _ ->
                throw :error
            end
          _, _ ->
            throw :error
        end)
      {:ok, {:dict, k_type, v_type}}

    catch
      :error -> {:error, ""}
    end
  end

  defp type_extension(_), do: {:error, ""}

  defp type_to_ast({:dict, arg1, arg2}) do
    {:dict, [], [type_to_ast(arg1), type_to_ast(arg2)]}
  end

  defp type_to_ast(arg), do: Util.type_to_ast(arg)

  defp value_to_type(nil), do: {:ok, :any}
  defp value_to_type(value), do: Util.value_to_type(value, &type_extension/1)
end

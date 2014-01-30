defmodule ExplexWeb.Util.Validation do
  alias Ecto.Query.Util

  def type(attr, value, expected, opts // []) do
    if Util.type_castable_to?(expected) do
      value = Util.try_cast(value, expected)
    end

    case value_to_type(value) do
      { :ok, type } ->
        if Util.type_eq?(expected, type) do
          []
        else
          str = type_to_ast(type) |> Macro.to_string
          expected_str = type_to_ast(expected) |> Macro.to_string
          [{ attr, opts[:message] || "wrong type: #{str}, expected: #{expected_str}" }]
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

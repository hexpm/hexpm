defmodule HexWeb.QueryAPI do
  defmacro coalesce(arg1, arg2) do
    quote do
      fragment("coalesce(?, ?)", unquote(arg1), unquote(arg2))
    end
  end
end

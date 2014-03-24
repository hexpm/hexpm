defmodule HexWeb.Plug do
  defmacro assign_pun(conn, vars) do
    Enum.reduce(vars, conn, fn { field, _, _ } = var, ast ->
      quote do
        Plug.Connection.assign(unquote(ast), unquote(field), unquote(var))
      end
    end)
  end
end

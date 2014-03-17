defmodule HexWeb.Plug do
  @doc """
  Forwards a connection matching given path to another router.
  """
  @spec forward(String.t, Macro.t, Plug.opts) :: Macro.t
  defmacro forward(path, plug, opts \\ []) do
    path = Path.join(path, "*glob")
    quote do
      match unquote(path) do
        conn = var!(conn).path_info(var!(glob))
        unquote(plug).call(conn, unquote(opts))
      end
    end
  end
end

defmodule HexWeb.Plug do
  import Plug.Conn

  defmodule BadRequest do
    defexception [:message]

    defimpl Plug.Exception do
      def status(_exception) do
        400
      end
    end
  end

  defmodule NotFound do
    defexception [:message]

    defimpl Plug.Exception do
      def status(_exception) do
        404
      end
    end
  end

  defmacro assign_pun(conn, vars) do
    Enum.reduce(vars, conn, fn { field, _, _ } = var, ast ->
      quote do
        Plug.Conn.assign(unquote(ast), unquote(field), unquote(var))
      end
    end)
  end

  def cache(conn, vary, control) do
    conn
    |> put_resp_header("vary", parse_vary(vary))
    |> put_resp_header("cache-control", parse_control(control))
  end

  defp parse_vary(vary) do
    Enum.map_join(vary, ", ", &"#{&1}")
  end

  defp parse_control(control) do
    Enum.map_join(control, ", ", fn
      atom when is_atom(atom) -> "#{atom}"
      { key, value }          -> "#{key}=#{value}"
    end)
  end

  def redirect(conn, url) do
    conn
    |> put_resp_header("location", url)
    |> send_resp(302, "")
  end
end

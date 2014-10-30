defmodule HexWeb.Plug do
  import Plug.Conn

  defmodule BadRequest do
    defexception [message: "Bad Request"]

    defimpl Plug.Exception do
      def status(_exception) do
        400
      end
    end
  end

  defmodule NotFound do
    defexception [message: "Not Found"]

    defimpl Plug.Exception do
      def status(_exception) do
        404
      end
    end
  end

  defmodule RequestTimeout do
    defexception [message: "Request Timeout"]

    defimpl Plug.Exception do
      def status(_exception) do
        408
      end
    end
  end

  defmodule RequestTooLarge do
    defexception [message: "Request Entity Too Large"]

    defimpl Plug.Exception do
      def status(_exception) do
        413
      end
    end
  end

  defmacro assign_pun(conn, vars) do
    Enum.reduce(vars, conn, fn {field, _, _} = var, ast ->
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
      {key, value}          -> "#{key}=#{value}"
    end)
  end

  def redirect(conn, url) do
    conn
    |> put_resp_header("location", url)
    |> send_resp(302, "")
  end

  def read_body_finally(conn) do
    register_before_send(conn, fn conn ->
      if conn.status in 200..399 do
        conn
      else
        # If we respond with an unsuccessful error code assume we did not read
        # body

        # Read the full body to avoid closing the connection too early :(
        # Works around getting H13/H18 errors on Heroku
        case read_body(conn, HexWeb.request_read_opts) do
          {:ok, _body, conn} -> conn
          _ -> conn
        end
      end
    end)
  end
end

defmodule HexWeb.Plugs.Redirect do
  import Plug.Connection

  def init(opts), do: opts

  def wrap(Plug.Conn[] = conn, opts, fun) do
    url = call Keyword.fetch!(opts, :to)

    case call opts[:ssl] do
      true -> if conn.scheme == :http, do: conn = redirect(conn, url)
      _ -> :ok
    end

    case conn.state == :unset && opts[:redirect] do
      redirects when is_list(redirects) ->
        conn =
          Enum.find_value(redirects, fn redirect ->
            if conn.host == call(redirect), do: redirect(conn, call url)
          end) || conn
      _ -> :ok
    end

    if conn.state == :unset, do: fun.(conn), else: conn
  end

  defp redirect(conn, url) do
    conn
    |> put_resp_header("location", url)
    |> send_resp(301, "")
  end

  defp call(fun) when is_function(fun), do: fun.()
  defp call(value), do: value
end

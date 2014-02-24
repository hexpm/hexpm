defmodule HexWeb.Plugs.Redirect do
  import Plug.Connection

  def init(opts), do: opts

  def wrap(Plug.Conn[] = conn, opts, fun) do
    url = Keyword.fetch!(opts, :to) |> call

    case Keyword.fetch(opts, :ssl) |> call do
      { :ok, true } -> if conn.scheme == :http, do: conn = redirect(conn, url)
      _ -> :ok
    end

    case conn.state == :unset && Keyword.fetch(opts, :redirect) |> call do
      { :ok, redirects } ->
        conn =
          Enum.find_value(redirects, fn redirect ->
            if conn.host == redirect, do: redirect(conn, url)
          end) || conn
      _ -> :ok
    end

    if conn.state == :unset, do: fun.(conn), else: conn
  end

  defp redirect(conn, url) do
    conn
    |> put_resp_header("location", url.())
    |> send_resp(301, "")
  end

  defp call(fun) when is_function(fun), do: fun.()
  defp call(value), do: value
end

defmodule HexpmWeb.Plugs.ReadOnly do
  import Plug.Conn

  alias Hexpm.OAuth.ReadOnly
  alias HexpmWeb.{ControllerHelpers, ErrorView}

  @safe_methods ~w(GET HEAD OPTIONS)
  @retry_after "60"

  def init(opts) do
    %{
      allowed_routes: Keyword.get(opts, :allowed_routes, []),
      write_routes: Keyword.get(opts, :write_routes, [])
    }
  end

  def call(conn, opts) do
    if ReadOnly.enabled?() and write_request?(conn, opts) and not allowed_route?(conn, opts) do
      unavailable(conn)
    else
      conn
    end
  end

  def prepare_unavailable(conn) do
    conn
    |> prevent_caching()
    |> put_private(:logster_log_level, :info)
    |> put_resp_header("retry-after", @retry_after)
  end

  def prevent_caching(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end

  def unavailable(conn) do
    conn
    |> prepare_unavailable()
    |> ControllerHelpers.render_error(503,
      error: "temporarily_unavailable",
      message: ErrorView.message("503")
    )
  end

  defp write_request?(conn, opts) do
    conn.method not in @safe_methods or route_matches?(conn, opts.write_routes)
  end

  defp allowed_route?(conn, opts) do
    route_matches?(conn, opts.allowed_routes)
  end

  defp route_matches?(conn, routes) do
    Enum.any?(routes, fn {method, path} ->
      method == conn.method and path_matches?(String.split(path, "/", trim: true), conn.path_info)
    end)
  end

  defp path_matches?([], []), do: true

  defp path_matches?([":" <> _parameter | expected], [_segment | actual]),
    do: path_matches?(expected, actual)

  defp path_matches?([segment | expected], [segment | actual]),
    do: path_matches?(expected, actual)

  defp path_matches?(_expected, _actual), do: false
end

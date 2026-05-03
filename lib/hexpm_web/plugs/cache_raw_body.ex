defmodule HexpmWeb.Plugs.CacheRawBody do
  @moduledoc """
  Reads and caches the raw request body for paths that need it before
  Plug.Parsers consumes the body. Stored in conn.assigns[:raw_body].

  Only activates for paths listed in :cache_raw_body_paths config, defaulting
  to ["/api/github/secret-scanning"].
  """

  @behaviour Plug

  require Logger

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if conn.request_path in paths() do
      case Plug.Conn.read_body(conn, length: 1_000_000) do
        {:ok, body, conn} ->
          Plug.Conn.assign(conn, :raw_body, body)

        {:more, _partial, conn} ->
          Logger.warning("CacheRawBody: body exceeded 1 MB limit for #{conn.request_path}")
          conn

        {:error, reason} ->
          Logger.warning("CacheRawBody: failed to read body: #{inspect(reason)}")
          conn
      end
    else
      conn
    end
  end

  defp paths do
    Application.get_env(:hexpm, :cache_raw_body_paths, ["/api/github/secret-scanning"])
  end
end

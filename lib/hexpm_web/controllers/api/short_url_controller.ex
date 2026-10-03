defmodule HexpmWeb.API.ShortURLController do
  use HexpmWeb, :controller
  alias Hexpm.ShortURLs
  alias HexpmWeb.Plugs.Attack

  def create(conn, params) do
    case ShortURLs.add(params, before_insert: fn -> throttle(conn) end) do
      {:ok, short_url} ->
        conn
        |> put_status(201)
        |> render(:show, url: url(~p"/l/#{short_url}"))

      {:error, {:throttle, _data} = throttle} ->
        Attack.block_action(conn, throttle, [])

      {:error, changeset} ->
        validation_failed(conn, changeset)
    end
  end

  defp throttle(conn) do
    case Attack.short_url_ip_throttle(conn.remote_ip) do
      {:allow, _data} -> :ok
      {:block, throttle} -> throttle
    end
  end
end

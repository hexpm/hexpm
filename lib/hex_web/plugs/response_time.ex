defmodule HexWeb.Plugs.ResponseTime do
  use Plug.Builder
  import Plug.Conn
  alias HexWeb.Util

  plug :put_resp_time

  def call(conn, opts) do
    put_resp_time(conn, opts)
  end

  def put_resp_time(conn, _) do
    conn
    |> put_private(:request_start, :os.timestamp)
    |> register_before_send fn conn ->
      response_time =  Util.format_response_time(conn.private[:request_start])

      conn
      |> put_resp_header("x-response-time", response_time)
    end
  end
end

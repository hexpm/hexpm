defmodule HexWeb.Plugs do
  import Plug.Conn, except: [read_body: 1]

  defmodule BadRequestError do
    defexception [plug_status: 400, message: "bad request"]
  end

  defmodule RequestTimeoutError do
    defexception [plug_status: 408, message: "request timeout"]
  end

  defmodule RequestTooLargeError do
    defexception [plug_status: 413, message: "request too large"]
  end

  # Max filesize: ~10mb
  # Min upload speed: ~10kb/s
  # Read 100kb every 10s
  @read_body_opts [
    length: 10_000_000,
    read_length: 100_000,
    read_timeout: 10_000
  ]

  def fetch_body(conn, _opts) do
    {conn, body} = read_body(conn)
    put_in(conn.params["body"], body)
  end

  def read_body_finally(conn, _opts) do
    register_before_send(conn, fn conn ->
      if conn.status in 200..399 do
        conn
      else
        # If we respond with an unsuccessful error code assume we did not read
        # body. Read the full body to avoid closing the connection too early,
        # works around getting H13/H18 errors on Heroku.
        case read_body(conn, @read_body_opts) do
          {:ok, _body, conn} -> conn
          _ -> conn
        end
      end
    end)
  end

  defp read_body(conn) do
    case read_body(conn, @read_body_opts) do
      {:ok, body, conn} ->
        {conn, body}
      {:error, :timeout} ->
        raise RequestTimeoutError
      {:error, _} ->
        raise BadRequestError
      {:more, _, _} ->
        raise RequestTooLargeError
    end
  end
end

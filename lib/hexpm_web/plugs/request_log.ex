defmodule HexpmWeb.Plugs.RequestLog do
  @moduledoc """
  Logs one line per request when the response is sent, with the method, path,
  status, duration and, once routed, the controller, action and format as
  metadata.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      duration_us =
        System.convert_time_unit(System.monotonic_time() - start, :native, :microsecond)

      Logger.info("#{conn.method} #{conn.request_path} #{conn.status}", fields(conn, duration_us))
      conn
    end)
  end

  defp fields(conn, duration_us) do
    [method: conn.method, path: conn.request_path, status: conn.status, duration_us: duration_us] ++
      routed(conn.private)
  end

  defp routed(%{phoenix_controller: controller, phoenix_action: action} = private) do
    [controller: inspect(controller), action: action, format: private[:phoenix_format]]
  end

  defp routed(_private), do: []
end

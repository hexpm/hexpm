defmodule HexpmWeb.Plugs.RequestLog do
  @moduledoc """
  Logs one `http.request` line per request when the response is sent, with the
  method, path, client IP, status, duration and, once routed, the controller,
  action and format as fields. A request that sends a `content-type` or
  `content-length` header also gets its value as `content_type` or
  `content_length`. A request authenticated with an API key, an OAuth token or
  a browser session also gets `credential`, `key:<id>`, `token:<jti>` or
  `session:<id>`, the same identifiers repo.hex.pm's access log uses and never
  the secret.
  """

  import Plug.Conn
  require Logger

  alias Hexpm.Accounts.Key
  alias Hexpm.OAuth.Token
  alias Hexpm.UserSession

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      duration_us =
        System.convert_time_unit(System.monotonic_time() - start, :native, :microsecond)

      Logger.info(line(conn, duration_us))
      conn
    end)
  end

  defp line(conn, duration_us) do
    Enum.into(body(conn) ++ routed(conn.private) ++ credential(conn.assigns), %{
      message: "HTTP request",
      event: "http.request",
      method: conn.method,
      path: conn.request_path,
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      status: conn.status,
      duration_us: duration_us
    })
  end

  defp body(conn) do
    for {field, header} <- [content_type: "content-type", content_length: "content-length"],
        value <- conn |> get_req_header(header) |> Enum.take(1) do
      {field, value}
    end
  end

  defp routed(%{phoenix_controller: controller, phoenix_action: action} = private) do
    [controller: inspect(controller), action: action] ++ format(private)
  end

  defp routed(_private), do: []

  defp format(%{phoenix_format: format}), do: [format: format]
  defp format(_private), do: []

  defp credential(%{auth_credential: %Key{id: id}}), do: [credential: "key:#{id}"]
  defp credential(%{auth_credential: %Token{jti: jti}}), do: [credential: "token:#{jti}"]
  defp credential(%{current_session: %UserSession{id: id}}), do: [credential: "session:#{id}"]
  defp credential(_assigns), do: []
end

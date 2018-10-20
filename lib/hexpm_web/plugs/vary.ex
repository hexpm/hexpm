defmodule HexpmWeb.Plugs.Vary do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, vary) do
    register_before_send(conn, fn conn ->
      original_vary = get_resp_header(conn, "vary")
      vary = Enum.join(original_vary ++ vary, ", ")
      put_resp_header(conn, "vary", vary)
    end)
  end
end

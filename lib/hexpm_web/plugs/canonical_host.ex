defmodule HexpmWeb.Plugs.CanonicalHost do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    canonical_host = Application.get_env(:hexpm, HexpmWeb.Endpoint)[:url][:host]

    if canonical_host && conn.host == "www.#{canonical_host}" do
      url = "https://#{canonical_host}#{conn.request_path}#{query_string(conn)}"

      conn
      |> put_resp_header("location", url)
      |> send_resp(301, "")
      |> halt()
    else
      conn
    end
  end

  defp query_string(%{query_string: ""}), do: ""
  defp query_string(%{query_string: qs}), do: "?#{qs}"
end

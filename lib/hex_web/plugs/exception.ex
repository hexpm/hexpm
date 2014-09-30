defmodule HexWeb.Plugs.Exception do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, [fun: fun]) do
    try do
      fun.(conn)
    catch
      kind, error ->
        stacktrace = System.stacktrace
        status     = Plug.Exception.status(error)

        if status == 500 do
          HexWeb.Util.log_error(kind, error, stacktrace)
        end

        if status != 500 and Exception.exception?(error) do
          message = Exception.message(error)
        end

        if List.first(conn.path_info) == "api" do
          api_response(conn, status, message)
        else
          html_response(conn, status, message)
        end
    end
  end

  defp html_response(conn, status, message) do
    conn
    |> assign(:status, status)
    |> assign(:message, message)
    |> HexWeb.Web.Router.send_page(:error)
    |> halt
  end

  defp api_response(conn, status, message) do
    conn =
      try do
        HexWeb.Plugs.Format.call(conn, [])
      catch
        _, _ -> conn
      end

    body = %{status: status}
    if message do
      body = Map.put(body, :message, message)
    end

    HexWeb.API.Util.send_body(conn, status, body, true)
    |> halt
  end
end

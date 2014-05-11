defmodule HexWeb.Plugs.Exception do
  @behaviour Plug.Wrapper

  import Plug.Conn

  def init(opts), do: opts

  def wrap(conn, _opts, fun) do
    try do
      fun.(conn)
    catch
      kind, error ->
        stacktrace = System.stacktrace
        status     = Plug.Exception.status(error)

        if status == 500, do: HexWeb.Util.log_error(kind, error, stacktrace)

        if List.first(conn.path_info) == "api" do
          api_response(conn, status)
        else
          html_response(conn, status)
        end
    end
  end

  defp html_response(conn, status) do
    conn
    |> assign(:status, status)
    |> HexWeb.Web.Router.send_page(:error)
  end

  defp api_response(conn, status) do
    conn =
      try do
        HexWeb.Plugs.Format.call(conn, [])
      catch
        _, _ -> conn
      end

    body = %{error: status}
    HexWeb.API.Util.send_render(conn, status, body, true)
  end
end

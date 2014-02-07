defmodule ExplexWeb.Router do
  use Plug.Router
  import Plug.Connection
  import ExplexWeb.Router.Util

  def call(conn, _opts) do
    exception_send_resp conn, fn ->
      dispatch(conn.method, conn.path_info, conn)
    end
  end

  forward "/api/beta", ExplexWeb.Router.API

  match _ do
    { :halt, send_resp(conn, 404, "") }
  end
end

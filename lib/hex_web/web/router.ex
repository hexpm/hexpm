defmodule HexWeb.Web.Router do
  use Plug.Router
  import Plug.Connection
  alias HexWeb.Web.Templates


  plug :match
  plug :dispatch

  get "/" do
    body = Templates.render(:my_page)
    send_resp(conn, 200, body)
  end

  match _ do
    send_resp(conn, 404, "404 FAIL")
  end
end

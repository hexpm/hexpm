defmodule ExplexWeb.Router do
  use Plug.Router
  import Plug.Connection
  import ExplexWeb.Router.Util

  plug ExplexWeb.Util.ExceptionPlug
  plug :match
  plug :dispatch

  forward "/api", ExplexWeb.Router.API

  match _ do
    send_resp(conn, 404, "")
  end
end

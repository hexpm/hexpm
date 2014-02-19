defmodule ExplexWeb.Router do
  use Plug.Router
  import Plug.Connection
  import ExplexWeb.Router.Util
  alias ExplexWeb.RegistryBuilder


  plug ExplexWeb.Plugs.Exception
  plug :match
  plug :dispatch


  get "api/registry" do
    conn = ExplexWeb.Plugs.Accept.call(conn, vendor: "explex", allow: ["dets"])
    send_file(conn, 200, RegistryBuilder.filename)
  end

  forward "/api", ExplexWeb.Router.API

  match _ do
    send_resp(conn, 404, "")
  end
end

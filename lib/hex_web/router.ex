defmodule HexWeb.Router do
  use Plug.Router
  import Plug.Connection
  import HexWeb.Router.Util
  alias HexWeb.RegistryBuilder


  plug HexWeb.Plugs.Exception
  plug :match
  plug :dispatch


  get "api/registry" do
    conn = HexWeb.Plugs.Accept.call(conn, vendor: "hex", allow: ["dets"])
    send_file(conn, 200, RegistryBuilder.latest_file)
  end

  forward "/api", HexWeb.Router.API

  match _ do
    send_resp(conn, 404, "")
  end
end

defmodule ExplexWeb.Router do
  use Plug.Router
  import Plug.Connection

  match _ do
    { :ok, send_resp(conn, 404, "") }
  end
end

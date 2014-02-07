defmodule ExplexWeb.Router.API do
  use Plug.Router
  import Plug.Connection
  import ExplexWeb.Router.Util
  alias ExplexWeb.User
  alias ExplexWeb.Package

  def call(conn, _opts) do
    case Plug.Parsers.call(conn, parsers: [ExplexWeb.Util.JsonDecoder]) do
      { :ok, conn } ->
        dispatch(conn.method, conn.path_info, conn)
      error ->
        error
    end
  end

  post "user" do
    User.create(conn.params["username"], conn.params["email"], conn.params["password"])
    |> send_creation_resp(conn)
  end

  post "package" do
    with_authorized do
      Package.create(conn.params["name"], user, conn.params["meta"])
      |> send_creation_resp(conn)
    end
  end

  match _ do
    { :halt, send_resp(conn, 404, "") }
  end
end

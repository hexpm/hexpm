defmodule ExplexWeb.Router.API do
  use Plug.Router
  import Plug.Connection
  import ExplexWeb.Router.Util
  alias ExplexWeb.User
  alias ExplexWeb.Package

  def call(conn, _opts) do
    if conn.method in ["POST", "PUT"] do
      case Plug.Parsers.call(conn, parsers: [ExplexWeb.Util.JsonDecoder]) do
        { :ok, conn } ->
          dispatch(conn.method, conn.path_info, conn)
        error ->
          error
      end
    else
      dispatch(conn.method, conn.path_info, conn)
    end
  end

  post "user" do
    User.create(conn.params["username"], conn.params["email"], conn.params["password"])
    |> send_creation_resp(conn)
  end

  put "package/:name" do
    with_authorized do
      if package = Package.get(name) do
        package.meta(conn.params["meta"])
        |> Package.update
        |> send_update_resp(conn)
      else
        Package.create(name, user, conn.params["meta"])
        |> send_creation_resp(conn)
      end
    end
  end

  match _ do
    { :halt, send_resp(conn, 404, "") }
  end
end

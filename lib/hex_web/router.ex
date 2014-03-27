defmodule HexWeb.Router do
  use Plug.Router
  import Plug.Connection
  alias HexWeb.Plugs
  alias HexWeb.Config

  plug :fetch
  plug Plugs.Exception
  plug Plugs.Forwarded
  plug Plugs.Redirect, ssl: &Config.use_ssl/0, redirect: [&Config.app_host/0], to: &Config.url/0
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Static, at: "/static", from: :hex_web
  plug :match
  plug :dispatch

  # TODO: favicon

  get "registry.ets.gz" do
    HexWeb.Config.store.registry(conn)
  end

  get "tarballs/:ball" do
    HexWeb.Config.store.tar(conn, ball)
  end

  forward "/api", to: HexWeb.API.Router

  match _ do
    HexWeb.Web.Router.call(conn, [])
  end

  defp fetch(conn, _opts) do
    fetch_params(conn)
  end
end

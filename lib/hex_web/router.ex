defmodule HexWeb.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.Plug
  alias HexWeb.Plugs
  alias HexWeb.Config

  plug Plugs.Exception
  plug Plugs.Forwarded
  plug Plugs.Redirect, ssl: &Config.use_ssl/0, redirect: [&Config.app_host/0], to: &Config.url/0

  plug :fetch

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Static, at: "/static", from: :hex_web

  plug :match
  plug :dispatch

  # TODO: favicon

  if Mix.env != :prod do
    get "registry.ets.gz" do
      HexWeb.Config.store.registry(conn)
    end

    get "tarballs/:ball" do
      HexWeb.Config.store.tar(conn, ball)
    end
  end

  get "installs/hex.ez" do
    case List.first get_req_header(conn, "user-agent") do
      "Mix/" <> version ->
        url = install_url(version)
      _ ->
        url = nil
    end

    url = url || "/installs/hex.ez"
    url = HexWeb.Config.cdn_url <> url

    conn
    |> cache([], [:public, "max-age": 60*60])
    |> redirect(url)
  end

  forward "/api", to: HexWeb.API.Router

  match _ do
    HexWeb.Web.Router.call(conn, [])
  end

  defp fetch(conn, _opts) do
    fetch_params(conn)
  end

  defp install_url(version) do
    case Version.parse(version) do
      {:ok, schema} ->
        if Version.match?(schema, ">= 0.13.1-dev") do
          "/installs/0.1.1/hex.ez"
        end
      :error ->
        nil
    end
  end
end

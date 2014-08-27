defmodule HexWeb.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.Plug
  alias HexWeb.Plugs

  def call(conn, opts) do
    Plugs.Exception.call(conn, [fun: &super(&1, opts)])
  end

  plug Plugs.Forwarded
  plug Plugs.Redirect,
    ssl: &__MODULE__.use_ssl/0,
    redirect: [&__MODULE__.app_host/0],
    to: &__MODULE__.url/0

  plug :fetch

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Static, at: "/static", from: :hex_web

  plug :match
  plug :dispatch

  # TODO: favicon

  if Mix.env != :prod do
    get "registry.ets.gz" do
      Application.get_env(:hex_web, :store).registry(conn)
    end

    get "tarballs/:ball" do
      Application.get_env(:hex_web, :store).tar(conn, ball)
    end
  end

  get "installs/hex.ez" do
    case List.first get_req_header(conn, "user-agent") do
      "Mix/" <> version ->
        latest = HexWeb.Install.latest(version)
      _ ->
        latest = nil
    end

    if latest do
      url = "installs/#{latest}/hex.ez"
    else
      url = "installs/hex.ez"
    end

    url = HexWeb.Util.cdn_url(url)

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

  def use_ssl do
    Application.get_env(:hex_web, :use_ssl)
  end

  def app_host do
    Application.get_env(:hex_web, :app_host)
  end

  def url do
    Application.get_env(:hex_web, :url)
  end
end

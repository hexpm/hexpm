defmodule HexWeb.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.Plug
  alias HexWeb.Plugs

  def call(conn, opts) do
    Plugs.Exception.call(conn, [fun: &super(&1, opts)])
  end

  plug Plugs.Forwarded
  plug HexWeb.BlockedAddress.Plug
  plug Plugs.Redirect,
    ssl: &__MODULE__.use_ssl/0,
    to: &__MODULE__.url/0

  plug :fetch

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Static, at: "/", from: :hex_web

  plug :match
  plug :dispatch

  # TODO: favicon

  # Used for testing this project and hex client
  if Mix.env != :prod do
    get "registry.ets.gz" do
      store = Application.get_env(:hex_web, :store)
      store.send_registry(conn)
    end

    get "tarballs/:ball" do
      store = Application.get_env(:hex_web, :store)
      store.send_release(conn, ball)
    end

    get "docs/:package/:version/*file" do
      store = Application.get_env(:hex_web, :store)
      path = Path.join([package, version, file])
      store.send_docs_page(conn, path)
    end
  end

  get "installs/hex.ez" do
    conn = fetch_params(conn)
    version = conn.params["elixir"]

    unless version do
      case List.first get_req_header(conn, "user-agent") do
        "Mix/" <> version ->
          version = version
        _ ->
          # Fallback to 1.0.0 because it did send headers and did not
          # send user-agent
          version = "1.0.0"
      end
    end

    latest = HexWeb.Install.latest(version)

    url =
      case latest do
        {:ok, _hex, elixir} ->
          # Always assume latest hex version
          "installs/#{elixir}/hex.ez"
        :error ->
          "installs/hex.ez"
      end
      |> HexWeb.Util.cdn_url

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

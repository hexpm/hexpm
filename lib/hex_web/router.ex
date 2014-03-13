defmodule HexWeb.Router do
  use Plug.Router
  import Plug.Connection
  import HexWeb.Router.Util
  import HexWeb.Util
  alias HexWeb.Plugs
  alias HexWeb.Config
  alias HexWeb.Package
  alias HexWeb.Release

  @parsers_opts [parsers: [HexWeb.Parsers.Json, HexWeb.Parsers.Elixir]]
  @accept_opts  [vendor: "hex", allow: [{"application","json"}, "json", "elixir"]]

  plug :fetch
  plug Plugs.Exception
  plug Plugs.Forwarded
  plug Plugs.Redirect, ssl: &Config.use_ssl/0, redirect: [&Config.app_host/0], to: &Config.url/0
  plug Plug.MethodOverride
  plug Plug.Head
  plug :match
  plug :dispatch


  get "installs" do
    body = [
      dev: [
        version: "0.0.1-dev",
        url: "http://s3.hex.pm/installs/hex.ez" ] ]

    conn
    |> Plug.Parsers.call(@parsers_opts)
    |> Plugs.Accept.call(@accept_opts)
    |> Plugs.Version.call([])
    |> send_render(200, body)
  end

  get "registry.ets.gz" do
    HexWeb.Config.store.registry(conn)
  end

  get "tarballs/:ball" do
    HexWeb.Config.store.tar(conn, ball)
  end

  post "api/packages/:name/releases" do
    if package = Package.get(name) do
      user_id = package.owner_id

      with_authorized_as(id: user_id) do
        { body, conn } = read_body!(conn, 10_000_000)
        conn = Plugs.Accept.call(conn, @accept_opts)

        case HexWeb.Tar.metadata(body) do
          { :ok, meta } ->
            version = meta["version"]
            git_url = meta["git_url"]
            git_ref = meta["git_ref"]
            reqs    = meta["requirements"]

            if release = Release.get(package, version) do
              result = Release.update(release, git_url, git_ref, reqs)
              if match?({ :ok, _ }, result), do: after_release(name, version, body)
              send_update_resp(result, conn)
            else
              result = Release.create(package, version, git_url, git_ref, reqs)
              if match?({ :ok, _ }, result), do: after_release(name, version, body)
              send_creation_resp(result, conn, api_url(["packages", name, "releases", version]))
            end

          { :error, errors } ->
            send_validation_failed(conn, errors)
        end
      end
    else
      send_resp(conn, 404, "")
    end
  end

  forward "/api", HexWeb.Router.API

  match _ do
    send_resp(conn, 404, "")
  end

  defp after_release(name, version, body) do
    HexWeb.Config.store.put_tar("#{name}-#{version}.tar", body)
    HexWeb.RegistryBuilder.rebuild
  end

  defp fetch(conn, _opts) do
    fetch_params(conn)
  end
end

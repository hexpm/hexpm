defmodule HexpmWeb.ReadmeController do
  use HexpmWeb, :controller

  alias Hexpm.Docs.Files
  alias Hexpm.Preview
  alias HexpmWeb.Readme.Renderer
  alias HexpmWeb.ReadmeToken

  plug :put_root_layout, false
  plug :put_layout, false

  @private_cache_control "private, no-store"

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
  end

  def show(conn, %{"repository" => repository, "version" => version, "token" => token} = params) do
    name = params["name"]

    case doc_kind(params) do
      nil ->
        not_found(conn, params)

      kind ->
        with :ok <- ReadmeToken.verify(token, repository, name, version),
             package when not is_nil(package) <- Packages.get(repository, name),
             release when not is_nil(release) <-
               Enum.find(Releases.all(package), &(to_string(&1.version) == version)) do
          serve_readme(conn, repository, package, release, kind, @private_cache_control)
        else
          _ -> send_no_readme(conn, @private_cache_control)
        end
    end
  end

  def show(conn, %{"repository" => _repository} = params) do
    not_found(conn, params)
  end

  def show(conn, %{"version" => version} = params) do
    name = params["name"]

    case doc_kind(params) do
      nil ->
        not_found(conn, params)

      kind ->
        with package when not is_nil(package) <- Packages.get("hexpm", name),
             release when not is_nil(release) <-
               Enum.find(Releases.all(package), &(to_string(&1.version) == version)) do
          serve_readme(conn, "hexpm", package, release, kind, "public, max-age=86400")
        else
          _ -> send_no_readme(conn)
        end
    end
  end

  def show(conn, params) do
    name = params["name"]

    case doc_kind(params) do
      nil ->
        not_found(conn, params)

      _kind ->
        case Releases.latest_version("hexpm", name,
               only_stable: true,
               unstable_fallback: true
             ) do
          nil ->
            send_no_readme(conn)

          version ->
            conn
            |> put_resp_header("cache-control", "public, max-age=3600")
            |> redirect(to: "/#{name}/#{version}#{redirect_query(params)}")
        end
    end
  end

  defp doc_kind(%{"kind" => kind}), do: Files.parse_segment(kind)
  defp doc_kind(_params), do: :readme

  defp redirect_query(%{"kind" => kind}), do: "?kind=#{kind}"
  defp redirect_query(_params), do: ""

  defp serve_readme(conn, repository, package, release, kind, cache_control) do
    version = to_string(release.version)

    case Preview.doc(repository, package.name, version, kind) do
      {:ok, filename, content} ->
        html = render_readme(repository, filename, content, package.name, version)

        conn
        |> put_resp_header("cache-control", cache_control)
        |> render(:show, readme_html: html, parent_origins: parent_origins())

      :error ->
        send_no_readme(conn, cache_control)
    end
  end

  defp render_readme(repository, filename, content, package_name, version) do
    Renderer.render(repository, filename, content, package_name, version)
  end

  defp send_no_readme(conn, cache_control \\ "public, max-age=3600") do
    conn
    |> put_resp_header("cache-control", cache_control)
    |> render(:no_readme, parent_origins: parent_origins())
  end

  defp parent_origins do
    case Application.get_env(:hexpm, :host) do
      nil -> ["*"]
      # TODO: Remove new.hex.pm when new.hex.pm replaces hex.pm
      host -> ["https://#{host}", "https://new.#{host}"]
    end
  end
end

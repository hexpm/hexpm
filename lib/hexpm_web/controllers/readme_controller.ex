defmodule HexpmWeb.ReadmeController do
  use HexpmWeb, :controller

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

    with :ok <- ReadmeToken.verify(token, repository, name, version),
         package when not is_nil(package) <- Packages.get(repository, name),
         release when not is_nil(release) <-
           Enum.find(Releases.all(package), &(to_string(&1.version) == version)) do
      serve_readme(conn, repository, package, release, @private_cache_control)
    else
      _ -> send_no_readme(conn, @private_cache_control)
    end
  end

  def show(conn, %{"repository" => _repository} = params) do
    not_found(conn, params)
  end

  def show(conn, %{"version" => version} = params) do
    name = params["name"]
    package = Packages.get("hexpm", name)

    if package do
      release = Enum.find(Releases.all(package), &(to_string(&1.version) == version))

      if release do
        serve_readme(conn, "hexpm", package, release, "public, max-age=86400")
      else
        send_no_readme(conn)
      end
    else
      send_no_readme(conn)
    end
  end

  def show(conn, params) do
    name = params["name"]
    package = Packages.get("hexpm", name)

    if package do
      releases = Releases.all(package)

      release =
        Hexpm.Repository.Release.latest_version(releases,
          only_stable: true,
          unstable_fallback: true
        )

      if release do
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> redirect(to: "/#{name}/#{release.version}")
      else
        send_no_readme(conn)
      end
    else
      send_no_readme(conn)
    end
  end

  defp serve_readme(conn, repository, package, release, cache_control) do
    version = to_string(release.version)

    case Preview.readme(repository, package.name, version) do
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

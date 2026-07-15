defmodule HexpmWeb.PreviewRedirectController do
  use HexpmWeb, :controller

  alias Hexpm.Preview

  def index(conn, _params), do: redirect_to(conn, "/packages")

  def sitemap(conn, _params), do: redirect_to(conn, "/preview/sitemap.xml")

  def package_sitemap(conn, %{"package" => package}) do
    redirect_to(conn, "/preview/#{URI.encode(package)}/sitemap.xml")
  end

  def latest(conn, %{"package" => package} = params) do
    redirect_latest(conn, package, params["filename"])
  end

  def latest_file(conn, %{"package" => package, "filename" => filename}) do
    redirect_latest(conn, package, filename)
  end

  def version(conn, %{"package" => package, "version" => version}) do
    redirect_source(conn, package, version, nil)
  end

  def version_file(conn, %{
        "package" => package,
        "version" => version,
        "filename" => filename
      }) do
    redirect_source(conn, package, version, filename)
  end

  def path(conn, %{"path" => ["preview", package, version, "show" | filename]}) do
    redirect_source(conn, package, version, filename)
  end

  def path(conn, %{"path" => ["preview", package, "show" | filename]}) do
    redirect_latest(conn, package, filename)
  end

  def path(conn, %{"path" => ["preview", package, version]}) do
    redirect_source(conn, package, version, nil)
  end

  def path(conn, %{"path" => ["preview", package]}) do
    redirect_latest(conn, package, nil)
  end

  def path(conn, _params), do: redirect_to(conn, conn.request_path)

  defp redirect_latest(conn, package, filename) do
    case Preview.get_latest_version(package) do
      version when is_binary(version) -> redirect_source(conn, package, version, filename)
      _ -> send_resp(conn, 404, "Not Found")
    end
  end

  defp redirect_source(conn, package, version, filename) do
    path =
      case filename do
        [_ | _] -> ~p"/packages/#{package}/#{version}/files/#{filename}"
        _ -> ~p"/packages/#{package}/#{version}/files"
      end

    redirect_to(conn, path)
  end

  defp redirect_to(conn, path) do
    query = if conn.query_string == "", do: "", else: "?#{conn.query_string}"

    conn
    |> put_status(:moved_permanently)
    |> redirect(external: HexpmWeb.Endpoint.url() <> path <> query)
  end
end

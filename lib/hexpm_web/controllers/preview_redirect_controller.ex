defmodule HexpmWeb.PreviewRedirectController do
  use HexpmWeb, :controller

  alias Hexpm.Preview

  def index(conn, _params), do: permanent_redirect(conn, "/packages")

  def sitemap(conn, _params), do: permanent_redirect(conn, "/preview/sitemap.xml")

  def package_sitemap(conn, %{"package" => package}) do
    permanent_redirect(conn, "/preview/#{URI.encode(package)}/sitemap.xml")
  end

  def latest(conn, %{"package" => package} = params) do
    redirect_latest(conn, package, params["filename"])
  end

  def latest_file(conn, %{"package" => package, "filename" => filename}) do
    redirect_latest(conn, package, filename)
  end

  def version(conn, %{"package" => package, "version" => version} = params) do
    redirect_source(conn, package, version, params["filename"])
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

  def path(conn, %{"path" => ["preview", package, version]} = params) do
    redirect_source(conn, package, version, params["filename"])
  end

  def path(conn, %{"path" => ["preview", package]} = params) do
    redirect_latest(conn, package, params["filename"])
  end

  def path(conn, _params), do: permanent_redirect(conn, conn.request_path)

  defp redirect_latest(conn, package, filename) do
    case Preview.get_latest_version("hexpm", package) do
      version when is_binary(version) -> redirect_source(conn, package, version, filename)
      _ -> send_resp(conn, 404, "Not Found")
    end
  end

  defp redirect_source(conn, package, version, filename) do
    path =
      case filename do
        [_ | _] ->
          ~p"/packages/#{package}/#{version}/files/#{filename}"

        filename when is_binary(filename) and filename != "" ->
          ~p"/packages/#{package}/#{version}/files/#{Path.split(filename)}"

        _ ->
          ~p"/packages/#{package}/#{version}/files"
      end

    query_string = conn.query_params |> Map.delete("filename") |> URI.encode_query()
    permanent_redirect(conn, path, query_string)
  end
end

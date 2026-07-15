defmodule HexpmWeb.PreviewRedirectController do
  use HexpmWeb, :controller

  def index(conn, _params), do: redirect_to(conn, "/packages")

  def sitemap(conn, _params), do: redirect_to(conn, "/preview/sitemap.xml")

  def package_sitemap(conn, %{"package" => package}) do
    redirect_to(conn, "/preview/#{URI.encode(package)}/sitemap.xml")
  end

  def path(conn, _params), do: redirect_to(conn, conn.request_path)

  defp redirect_to(conn, path) do
    query = if conn.query_string == "", do: "", else: "?#{conn.query_string}"

    conn
    |> put_status(:moved_permanently)
    |> redirect(external: HexpmWeb.Endpoint.url() <> path <> query)
  end
end

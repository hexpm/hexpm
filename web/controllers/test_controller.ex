defmodule HexWeb.TestController do
  use HexWeb.Web, :controller

  def get_registry(conn, _params) do
    registry = HexWeb.Store.get(nil, :s3_bucket, "registry.ets.gz", [])

    if signature = HexWeb.Store.get(nil, :s3_bucket, "registry.ets.gz.signed", []) do
      conn
      |> put_resp_header("x-hex-signature", signature)
      |> send_resp(200, registry)
    else
      send_resp(conn, 200, registry)
    end
  end

  def get_registry_signed(conn, _params) do
    HexWeb.Store.get(nil, :s3_bucket, "registry.ets.gz.signed", [])
    |> send_object(conn)
  end

  def get_names(conn, _params) do
    HexWeb.Store.get(nil, :s3_bucket, "names", [])
    |> send_object(conn)
  end

  def get_versions(conn, _params) do
    HexWeb.Store.get(nil, :s3_bucket, "versions", [])
    |> send_object(conn)
  end

  def get_package(conn, %{"package" => package}) do
    HexWeb.Store.get(nil, :s3_bucket, "packages/#{package}", [])
    |> send_object(conn)
  end

  def get_tarball(conn, %{"ball" => ball}) do
    HexWeb.Store.get(nil, :s3_bucket, "tarballs/#{ball}", [])
    |> send_object(conn)
  end

  def get_docs_page(conn, params) do
    path = Path.join([params["package"], params["version"], params["page"]])
    HexWeb.Store.get(nil, :docs_bucket, path, [])
    |> send_object(conn)
  end

  def get_docs_sitemap(conn, _params) do
    HexWeb.Store.get(nil, :docs_bucket, "sitemap.xml", [])
    |> send_object(conn)
  end

  def get_installs_csv(conn, _params) do
    send_resp(conn, 200, "")
  end

  defp send_object(nil, conn), do: send_resp(conn, 404, "")
  defp send_object(obj, conn), do: send_resp(conn, 200, obj)
end

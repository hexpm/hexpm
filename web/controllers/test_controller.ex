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
    if signature = HexWeb.Store.get(nil, :s3_bucket, "registry.ets.gz.signed", []) do
      send_resp(conn, 200, signature)
    else
      send_resp(conn, 404, "")
    end
  end

  def get_tarball(conn, params) do
    if ball = HexWeb.Store.get(nil, :s3_bucket, "tarballs/#{params["ball"]}", []) do
      send_resp(conn, 200, ball)
    else
      send_resp(conn, 404, "")
    end
  end

  def get_docs_page(conn, params) do
    path = Path.join([params["package"], params["version"], params["page"]])
    if page = HexWeb.Store.get(nil, :docs_bucket, path, []) do
      send_resp(conn, 200, page)
    else
      send_resp(conn, 404, "")
    end
  end

  def get_docs_sitemap(conn, _params) do
    if page = HexWeb.Store.get(nil, :docs_bucket, "sitemap.xml", []) do
      send_resp(conn, 200, page)
    else
      send_resp(conn, 404, "")
    end
  end
end

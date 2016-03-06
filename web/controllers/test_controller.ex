defmodule HexWeb.TestController do
  use HexWeb.Web, :controller

  def get_registry(conn, _params) do
    HexWeb.Store.send_registry(conn)
  end

  def get_registry_signed(conn, _params) do
    HexWeb.Store.send_registry_signature(conn)
  end

  def get_tarball(conn, params) do
    HexWeb.Store.send_release(conn, params["ball"])
  end

  def get_docs_page(conn, params) do
    path = Path.join([params["package"], params["version"], params["page"]])
    HexWeb.Store.send_docs_page(conn, path)
  end

  def get_docs_sitemap(conn, _params) do
    HexWeb.Store.send_docs_page(conn, "sitemap.xml")
  end
end

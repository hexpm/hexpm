defmodule HexWeb.TestController do
  use HexWeb.Web, :controller

  def get_registry(conn, _params) do
    Application.get_env(:hex_web, :store)
               .send_registry(conn)
  end

  def get_registry_signed(conn, _params) do
    Application.get_env(:hex_web, :store)
               .send_registry_signature(conn)
  end

  def get_tarball(conn, params) do
    Application.get_env(:hex_web, :store)
               .send_release(conn, params["ball"])
  end

  def get_docs_page(conn, params) do
    path = Path.join([params["package"], params["version"], params["page"]])
    Application.get_env(:hex_web, :store)
               .send_docs_page(conn, path)
  end
end

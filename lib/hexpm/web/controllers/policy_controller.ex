defmodule Hexpm.Web.PolicyController do
  use Hexpm.Web, :controller

  def coc(conn, _params) do
    render(
      conn,
      "coc.html",
      title: "Code of Conduct",
      container: "container page page-sm policies"
    )
  end

  def copyright(conn, _params) do
    render(
      conn,
      "copyright.html",
      title: "Copyright Policy",
      container: "container page page-sm policies"
    )
  end

  def privacy(conn, _params) do
    render(
      conn,
      "privacy.html",
      title: "Privacy Policy",
      container: "container page page-sm policies"
    )
  end

  def tos(conn, _params) do
    render(
      conn,
      "tos.html",
      title: "Terms of Service",
      container: "container page page-sm policies"
    )
  end
end

defmodule HexWeb.PolicyController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    render conn, "index.html", [
      active: :docs,
      title: "Policies"
    ]
  end

  def coc(conn, _params) do
    render conn, "coc.html", [
      active: :docs,
      title: "Code of Conduct"
    ]
  end

  def copyright(conn, _params) do
    render conn, "copyright.html", [
      active: :docs,
      title: "Copyright Policy"
    ]
  end

  def privacy(conn, _params) do
    render conn, "privacy.html", [
      active: :docs,
      title: "Privacy Policy"
    ]
  end

  def tos(conn, _params) do
    render conn, "tos.html", [
      active: :docs,
      title: "Terms of Service"
    ]
  end
end

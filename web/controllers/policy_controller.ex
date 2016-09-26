defmodule HexWeb.PolicyController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    render conn, "index.html", [
      title: "Policies"
    ]
  end

  def coc(conn, _params) do
    render conn, "coc.html", [
      title: "Code of Conduct"
    ]
  end

  def copyright(conn, _params) do
    render conn, "copyright.html", [
      title: "Copyright Policy"
    ]
  end

  def privacy(conn, _params) do
    render conn, "privacy.html", [
      title: "Privacy Policy"
    ]
  end

  def tos(conn, _params) do
    render conn, "tos.html", [
      title: "Terms of Service"
    ]
  end
end

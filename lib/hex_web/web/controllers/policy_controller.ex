defmodule HexWeb.PolicyController do
  use HexWeb.Web, :controller

  def index(conn, _params) do
    render conn, "index.html", [
      title: "Policies",
      container: "container page policy"
    ]
  end

  def coc(conn, _params) do
    render conn, "coc.html", [
      title: "Code of Conduct",
      container: "container page policy"
    ]
  end

  def copyright(conn, _params) do
    render conn, "copyright.html", [
      title: "Copyright Policy",
      container: "container page policy"
    ]
  end

  def privacy(conn, _params) do
    render conn, "privacy.html", [
      title: "Privacy Policy",
      container: "container page policy"
    ]
  end

  def tos(conn, _params) do
    render conn, "tos.html", [
      title: "Terms of Service",
      container: "container page policy"
    ]
  end
end

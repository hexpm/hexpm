defmodule HexWeb.PolicyController do
  use HexWeb.Web, :controller

  def coc(conn, _params) do
    render conn, "coc.html", [
      active: :policy,
      title: "Code of Conduct"
    ]
  end

  def copyright(conn, _params) do
    render conn, "copyright.html", [
      active: :policy,
      title: "Copyright Policy"
    ]
  end

  def privacy(conn, _params) do
    render conn, "privacy.html", [
      active: :policy,
      title: "Privacy Policy"
    ]
  end

  def tos(conn, _params) do
    render conn, "tos.html", [
      active: :policy,
      title: "Terms of Service"
    ]
  end
end

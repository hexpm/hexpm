defmodule HexWeb.PolicyController do
  use HexWeb.Web, :controller

  def coc(conn, _params) do
    render conn, "coc.html", [
      active: :policy,
      title: "Code of Conduct"
    ]
  end

  def privacy(conn, _params) do
    render conn, "privacy.html", [
      active: :policy,
      title: "Privacy Policy"
    ]
  end
end

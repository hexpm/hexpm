defmodule HexpmWeb.PolicyController do
  use HexpmWeb, :controller

  def coc(conn, _params) do
    render(
      conn,
      "coc.html",
      title: "Code of Conduct",
      container: "policy grid place-content-center space-y-8"
    )
  end

  def copyright(conn, _params) do
    render(
      conn,
      "copyright.html",
      title: "Copyright Policy",
      container: "policy grid place-content-center space-y-8"
    )
  end

  def privacy(conn, _params) do
    render(
      conn,
      "privacy.html",
      title: "Privacy Policy",
      container: "policy grid place-content-center space-y-8"
    )
  end

  def tos(conn, _params) do
    render(
      conn,
      "tos.html",
      title: "Terms of Service",
      container: "policy grid place-content-center space-y-8"
    )
  end

  def dispute(conn, _params) do
    render(
      conn,
      "dispute.html",
      title: "Naming Dispute Policy",
      container: "policy grid place-content-center space-y-8"
    )
  end
end

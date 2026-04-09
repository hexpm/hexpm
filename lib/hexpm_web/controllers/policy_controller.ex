defmodule HexpmWeb.PolicyController do
  use HexpmWeb, :controller

  def coc(conn, _params) do
    render(
      conn,
      "coc.html",
      title: "Code of Conduct",
      container: "flex-1 flex flex-col"
    )
  end

  def copyright(conn, _params) do
    render(
      conn,
      "copyright.html",
      title: "Copyright Policy",
      container: "flex-1 flex flex-col"
    )
  end

  def privacy(conn, _params) do
    render(
      conn,
      "privacy.html",
      title: "Privacy Policy",
      container: "flex-1 flex flex-col"
    )
  end

  def tos(conn, _params) do
    render(
      conn,
      "tos.html",
      title: "Terms of Service",
      container: "flex-1 flex flex-col"
    )
  end

  def dispute(conn, _params) do
    render(
      conn,
      "dispute.html",
      title: "Dispute policy",
      container: "flex-1 flex flex-col"
    )
  end
end

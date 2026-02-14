defmodule HexpmWeb.PolicyController do
  use HexpmWeb, :controller

  def coc(conn, _params) do
    render(
      conn,
      "coc.html",
      title: "Code of Conduct",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def copyright(conn, _params) do
    render(
      conn,
      "copyright.html",
      title: "Copyright Policy",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def privacy(conn, _params) do
    render(
      conn,
      "privacy.html",
      title: "Privacy Policy",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def tos(conn, _params) do
    render(
      conn,
      "tos.html",
      title: "Terms of Service",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def dispute(conn, _params) do
    render(
      conn,
      "dispute.html",
      title: "Dispute policy",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end
end

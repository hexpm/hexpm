defmodule HexpmWeb.PolicyController do
  use HexpmWeb, :controller

  def coc(conn, _params) do
    render_layout(conn, "coc.html", "Code of Conduct")
  end

  def copyright(conn, _params) do
    render_layout(conn, "copyright.html", "Copyright Policy")
  end

  def privacy(conn, _params) do
    render_layout(conn, "privacy.html", "Privacy Policy")
  end

  def tos(conn, _params) do
    render_layout(conn, "tos.html", "Terms of Service")
  end

  def dispute(conn, _params) do
    render_layout(conn, "dispute.html", "Naming Dispute Policy")
  end

  defp render_layout(conn, view, title) do
    render(conn, "layout.html", view: view, title: title, container: nil)
  end
end

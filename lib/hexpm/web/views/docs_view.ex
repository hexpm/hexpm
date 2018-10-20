defmodule HexpmWeb.DocsView do
  use HexpmWeb, :view
  alias HexpmWeb.DocsView

  def selected_docs(conn, view) do
    if conn.assigns.view_name == view do
      "selected"
    else
      ""
    end
  end
end

defmodule Hexpm.Web.DocsView do
  use Hexpm.Web, :view
  alias Hexpm.Web.DocsView

  def selected_docs(conn, view) do
    if conn.assigns.view_name == view do
      "selected"
    else
      ""
    end
  end
end

defmodule Hexpm.OpenSearchController do
  use Hexpm.Web, :controller

  def opensearch(conn, _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> render("opensearch.xml")
  end
end

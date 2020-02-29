defmodule HexpmWeb.FeedsController do
  use HexpmWeb, :controller

  def blog(conn, _params) do
    conn
    |> put_view(HexpmWeb.BlogView)
    |> put_resp_content_type("application/rss+xml")
    |> render("index.xml")
  end
end

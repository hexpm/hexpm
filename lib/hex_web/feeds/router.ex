defmodule HexWeb.Feeds.Router do
  use Plug.Router
  import Plug.Conn
  import HexWeb.Plug
  require EEx
  alias HexWeb.Plug.NotFound
  alias HexWeb.Package

  plug :match
  plug :dispatch

  get "/new-packages.rss" do
    packages = Package.recent_full(30)

    conn = assign_pun(conn, [packages])
    body = template_new_packages_rss(conn.assigns)

    send_rss(conn, body)
  end

  match _ do
    _conn = conn
    raise NotFound
  end

  # Creating a eex template function for 'new-packages.rss.eex'.
  EEx.function_from_file(:defp, :"template_new_packages_rss",
    Path.join([__DIR__, "templates", "new-packages.rss.eex"]), [:assigns], engine: HexWeb.Web.HTML.Engine)

  # Partial template for the metadata.
  EEx.function_from_file(:defp, :"partial_meta_to_description",
    Path.join([__DIR__, "templates/partials", "meta_to_description.eex"]), [:assigns], engine: HexWeb.Web.HTML.Engine)

  # Sending RSS XML content
  defp send_rss(conn, body) do
    status = conn.assigns[:status] || 200

    conn
    |> put_resp_header("content-type", "application/rss+xml")
    |> send_resp(status, body)
  end

end

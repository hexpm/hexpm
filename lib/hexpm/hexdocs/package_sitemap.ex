defmodule Hexpm.Hexdocs.PackageSitemap do
  require EEx

  template = ~S"""
  <?xml version="1.0" encoding="utf-8"?>
  <urlset
      xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">
  <%= for page <- pages do %>
    <url>
      <loc><%= xml_escape(Hexpm.Utils.docs_html_url("hexpm", package_name, "/" <> encode_path(page))) %></loc>
      <lastmod><%= format_datetime updated_at %></lastmod>
      <changefreq>daily</changefreq>
      <priority>0.8</priority>
    </url>
  <% end %>
  </urlset>
  """

  EEx.function_from_string(:def, :render, template, [:package_name, :pages, :updated_at])

  defp format_datetime(datetime) do
    datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  # Page names come out of the uploaded tarball, so one `&` in a filename would
  # otherwise take the whole sitemap down with it.
  defp encode_path(path) do
    URI.encode(path, &(&1 == ?/ or URI.char_unreserved?(&1)))
  end

  defp xml_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end

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
      <loc><%= Hexpm.Utils.docs_html_apex_url(package_name) <> page %></loc>
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
end

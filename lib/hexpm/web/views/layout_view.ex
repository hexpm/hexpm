defmodule Hexpm.Web.LayoutView do
  use Hexpm.Web, :view

  def show_search?(assigns) do
    Map.get(assigns, :hide_search) != true
  end

  def title(assigns) do
    if title = Map.get(assigns, :title) do
      "#{title} | Hex"
    else
      "Hex"
    end
  end

  def description(assigns) do
    if description = Map.get(assigns, :description) do
      String.slice(description, 0, 160)
    else
      "A package manager for the Erlang ecosystem"
    end
  end

  def canonical_url(assigns) do
    if url = Map.get(assigns, :canonical_url) do
      tag(:link, rel: "canonical", href: url)
    else
      nil
    end
  end

  def search(assigns) do
    Map.get(assigns, :search)
  end

  def container_class(assigns) do
    Map.get(assigns, :container, "container page")
  end

  def og_tags(assigns) do
    [
      tag(:meta, property: "og:title", content: Map.get(assigns, :title)),
      tag(:meta, property: "og:type", content: "website"),
      tag(:meta, property: "og:url", content: Map.get(assigns, :canonical_url)),
      tag(:meta, property: "og:image", content: static_url(Hexpm.Web.Endpoint, "/images/open-graph.png")),
      tag(:meta, property: "og:image:width", content: "1200"),
      tag(:meta, property: "og:image:height", content: "630"),
      tag(:meta, property: "og:description", content: description(assigns)),
      tag(:meta, property: "og:site_name", content: "Hex"),
      tag(:meta, property: "twitter:card", content: "summary_large_image"),
      tag(:meta, property: "twitter:site", content: "@hex_pm"),
      tag(:meta, property: "twitter:creator", content: "@hex_pm"),
      tag(:meta, property: "twitter:title", content: Map.get(assigns, :title)),
      tag(:meta, property: "twitter:description", content: description(assigns)),
      tag(:meta, property: "twitter:image", content: static_url(Hexpm.Web.Endpoint, "/images/open-graph.png"))
    ]
  end
end

defmodule HexWeb.LayoutView do
  use HexWeb.Web, :view

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

  def active(assigns, page) do
    if Map.get(assigns, :active) == page do
      raw ~s( class="active")
    end
  end

  def search(assigns) do
    Map.get(assigns, :search)
  end
end

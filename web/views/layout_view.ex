defmodule HexWeb.LayoutView do
  use HexWeb.Web, :view

  def title(assigns) do
    if title = Map.get(assigns, :title) do
      "#{title} | Hex"
    else
      "Hex"
    end
  end

  def active(assigns, page) do
    if Map.get(assigns, :active) == page do
      ~s(class="active")
    end
  end

  def search(assigns) do
    Map.get(assigns, :search)
  end
end

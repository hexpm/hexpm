defmodule HexpmWeb.PageView do
  use HexpmWeb, :view

  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Home
  import HexpmWeb.Components.Pricing
  import HexpmWeb.Components.Sponsors

  def render_package(data) do
    data =
      [
        downloads: nil,
        description: nil,
        inserted_at: nil,
        version: nil
      ]
      |> Keyword.merge(data)

    render("_package.html", data)
  end
end

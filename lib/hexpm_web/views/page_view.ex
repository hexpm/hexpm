defmodule HexpmWeb.PageView do
  use HexpmWeb, :view

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

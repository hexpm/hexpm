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

  def most_downloaded_package(package_top) do
    Enum.at(package_top, 0)
  end
end

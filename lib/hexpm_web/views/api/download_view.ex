defmodule HexpmWeb.API.DownloadView do
  use HexpmWeb, :view

  def render("show." <> _, %{download: download}) do
    render_one(download, __MODULE__, "show")
  end

  def render("show", %{download: download}) do
    %{download.view => download.downloads}
  end
end

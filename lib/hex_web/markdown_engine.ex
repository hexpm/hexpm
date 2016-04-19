defmodule HexWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  def compile(path, _name) do
    html =
      path
      |> File.read!
      |> Earmark.to_html(%Earmark.Options{gfm: true})

    {:safe, html}
  end
end

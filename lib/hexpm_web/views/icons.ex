defmodule HexpmWeb.ViewIcons do
  use Phoenix.HTML

  @icons_dir Path.join(__DIR__, "../../../assets/vendor/icons")
  @heroicons_svg Path.join(@icons_dir, "heroicons.svg")

  @external_resource @heroicons_svg

  doc = File.read!(@heroicons_svg)

  defp heroicon(title) when is_atom(title), do: heroicon(Atom.to_string(title))

  doc
  |> String.split("\n")
  |> Enum.each(fn line ->
    case Regex.named_captures(~r/\<g title=\"(?<title>[\w\d\-]+)\"/, line) do
      %{"title" => title} -> defp heroicon(unquote(title)), do: unquote(line)
      _ -> :noop
    end
  end)

  def icon(type, title, opts \\ [])

  def icon(:heroicon, title, opts) do
    class = "heroicon heroicon-#{title}"
    g_tag = heroicon(title)

    opts =
      opts
      |> Keyword.put_new(:"aria-hidden", "true")
      |> Keyword.put_new(:version, "1.1")
      |> Keyword.put_new(:viewBox, "0 0 24 24")
      |> Keyword.put_new(:width, 24)
      |> Keyword.put_new(:height, 24)
      |> Keyword.put_new(:fill, "none")
      |> Keyword.put_new(:title, title)
      |> Keyword.update(:class, class, &"#{class} #{&1}")

    content_tag(:svg, opts, do: raw(g_tag))
  end

  def icon(_any, _name, _opts), do: nil
end

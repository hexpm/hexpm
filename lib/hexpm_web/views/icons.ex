defmodule HexpmWeb.ViewIcons do
  use Phoenix.HTML
  import SweetXml

  @icons_dir Path.join(__DIR__, "../../../assets/vendor/icons")
  @remixicon_svg Path.join(@icons_dir, "remixicon.svg")

  @external_resource @remixicon_svg

  doc = File.read!(@remixicon_svg)

  remixicon =
    SweetXml.xpath(
      doc,
      ~x"//glyph"l,
      name: ~x"./@glyph-name"s,
      d: ~x"./@d"s,
      x: ~x"./@horiz-adv-x"s
    )

  defp remixicon(name) when is_atom(name), do: remixicon(Atom.to_string(name))

  Enum.each(remixicon, fn %{name: name, d: d, x: x} ->
    defp remixicon(unquote(name)), do: {unquote(d), unquote(x)}
  end)

  def icon(type, name, opts \\ [])

  def icon(:remixicon, name, opts) do
    class = "remixicon remixicon-#{name}"
    {d, x} = remixicon(name)
    title = if title = opts[:title], do: content_tag(:title, title), else: ""

    opts =
      opts
      |> Keyword.put_new(:"aria-hidden", true)
      |> Keyword.put_new(:version, "1.1")
      |> Keyword.put_new(:viewBox, "0 0 #{x} #{x}")
      |> Keyword.update(:class, class, &"#{class} #{&1}")
      |> Keyword.drop([:title])

    content_tag :svg, opts do
      content_tag :g, transform: "translate(0, #{x}) scale(1, -1)" do
        [content_tag(:path, "", d: d), title]
      end
    end
  end

  # TODO: Remove when all glyphicons are removed
  def icon(:glyphicon, _name, _opts) do
    raw("<div></div>")
  end

  # TODO: Remove when all octicons are removed
  def icon(:octicon, _name, _opts) do
    raw("<div></div>")
  end
end

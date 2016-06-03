defmodule HexWeb.ViewIcons do
  use Phoenix.HTML
  import SweetXml

  @octicons_path Path.join(__DIR__, "../static/vendor/icons/octicons.svg")
  @external_resource @octicons_path

  doc = File.read!(@octicons_path)

  octicons = SweetXml.xpath(doc, ~x"//glyph"l,
    name: ~x"./@glyph-name"s,
    d: ~x"./@d"s,
    x: ~x"./@horiz-adv-x"s
  )

  defp icon_properties(type, name) when is_atom(name),
    do: icon_properties(type, Atom.to_string(name))

  Enum.each(octicons, fn %{name: name, d: d, x: x} ->
    defp icon_properties(:octicon, unquote(name)), do: {unquote(d), unquote(x)}
  end)

  def icon(type, name, opts) do
    class = "#{type} #{type}-#{name}"
    {d, x} = icon_properties(type, name)

    opts =
      opts
      |> Keyword.put_new(:"aria-hidden", true)
      |> Keyword.put_new(:version, "1.1")
      |> Keyword.put_new(:viewBox, "0 0 #{x} 1024")
      |> Keyword.update(:class, class, &"#{class} #{&1}")

    content_tag(:svg, opts) do
      content_tag(:g, transform: "translate(0, 800) scale(1, -1)") do
        tag(:path, d: d)
      end
    end
  end
end

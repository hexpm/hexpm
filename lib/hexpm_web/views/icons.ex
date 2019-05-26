defmodule HexpmWeb.ViewIcons do
  use Phoenix.HTML
  import SweetXml

  @icons_dir Path.join(__DIR__, "../../../assets/vendor/icons")
  @octicons_svg Path.join(@icons_dir, "octicons.svg")
  @glyphicons_svg Path.join(@icons_dir, "glyphicons-halflings-regular.svg")
  @glyphicons_less Path.join(@icons_dir, "glyphicons.less")

  @external_resource @octicons_svg
  @external_resource @glyphicons_svg
  @external_resource @glyphicons_less

  :ok = Application.load(:xmerl)
  {:ok, xmerl_version} = :application.get_key(:xmerl, :vsn)

  xmerl_version =
    xmerl_version
    |> List.to_string()
    |> String.split(".")
    |> Enum.take(3)
    |> Enum.join(".")

  broken_xmerl? = Version.compare(xmerl_version, "1.3.20") == :lt

  doc = File.read!(@octicons_svg)

  octicons =
    SweetXml.xpath(
      doc,
      ~x"//glyph"l,
      name: ~x"./@glyph-name"s,
      d: ~x"./@d"s,
      x: ~x"./@horiz-adv-x"s
    )

  defp octicon(name) when is_atom(name), do: octicon(Atom.to_string(name))

  Enum.each(octicons, fn %{name: name, d: d, x: x} ->
    defp octicon(unquote(name)), do: {unquote(d), unquote(x)}
  end)

  doc = File.read!(@glyphicons_svg)

  glyphicons =
    SweetXml.xpath(
      doc,
      ~x"//glyph[@unicode][@d]"l,
      unicode: if(broken_xmerl?, do: ~x"./@unicode", else: ~x"./@unicode"s),
      d: ~x"./@d"s,
      x: ~x"./@horiz-adv-x"s
    )

  lines =
    File.read!(@glyphicons_less)
    |> String.split("\n", trim: true)

  @glyphicon_less_regex ~r'\.glyphicon-([-\w]+)\s*\{ &:before \{ content: "\\([0-9a-f]{4})"; \} \}'
  glyphicon_names =
    Enum.reduce(lines, %{}, fn line, map ->
      case Regex.run(@glyphicon_less_regex, line) do
        [_, name, content] ->
          Map.put(map, content, name)

        nil ->
          map
      end
    end)

  defp glyphicon(name) when is_atom(name), do: glyphicon(Atom.to_string(name))

  Enum.each(glyphicons, fn %{unicode: unicode, d: d, x: x} ->
    unicode = if broken_xmerl?, do: IO.iodata_to_binary(Enum.reverse(unicode)), else: unicode

    name =
      case unicode do
        <<char::utf8>> ->
          codepoint =
            char
            |> Integer.to_string(16)
            |> String.pad_leading(4, "0")
            |> String.downcase()

          Map.get(glyphicon_names, codepoint)
      end

    if name do
      defp glyphicon(unquote(name)), do: {unquote(d), unquote(x)}
    end
  end)

  def icon(type, name, opts \\ [])

  def icon(:octicon, name, opts) do
    class = "octicon octicon-#{name}"
    {d, x} = octicon(name)
    title = if title = opts[:title], do: content_tag(:title, title), else: ""

    opts =
      opts
      |> Keyword.put_new(:"aria-hidden", true)
      |> Keyword.put_new(:version, "1.1")
      |> Keyword.put_new(:viewBox, "0 0 #{x} 1024")
      |> Keyword.update(:class, class, &"#{class} #{&1}")
      |> Keyword.drop([:title])

    content_tag :svg, opts do
      content_tag :g, transform: "translate(0, 800) scale(1, -1)" do
        [content_tag(:path, "", d: d), title]
      end
    end
  end

  def icon(:glyphicon, name, opts) do
    class = "glyphicon glyphicon-#{name}"
    {d, x} = glyphicon(name)
    x = if x == "", do: "1200", else: x
    title = if title = opts[:title], do: content_tag(:title, title), else: ""

    opts =
      opts
      |> Keyword.put_new(:"aria-hidden", true)
      |> Keyword.put_new(:version, "1.1")
      |> Keyword.put_new(:viewBox, "0 0 #{x} 1200")
      |> Keyword.update(:class, class, &"#{class} #{&1}")
      |> Keyword.drop([:title])

    content_tag :svg, opts do
      content_tag :g, transform: "translate(0, 1200) scale(1, -1)" do
        [content_tag(:path, "", d: d), title]
      end
    end
  end
end

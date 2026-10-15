defmodule Hexpm.Hexdocs.FileRewriter do
  @link_addition ~s|<a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|
  @link_hooks [
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" rel="noopener" title="@dignifiedquire">Friedel Ziegelmayer</a>|,
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  ]
  @analytics_addition "<script async defer src=\"https://s.${DOMAIN}/js/script.js\"></script><script>window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init({endpoint:\"https://s.${DOMAIN}/api/event\"})</script>"
  @official_domains ~w(hex.pm hexdocs.pm hexorgs.pm elixir-lang.org erlang.org)
  # Elements whose content the browser reads as text up to their end tag.
  @raw_text_elements ~w(style textarea title xmp iframe noembed noframes)
  # Start tags that close every open SVG and MathML element.
  @breakout_tags ~w(b big blockquote body br center code dd div dl dt em embed h1 h2 h3 h4 h5 h6
                    head hr i img li listing menu meta nobr ol p pre ruby s small span strong
                    strike sub sup table tt u ul var)
  # SVG and MathML elements whose content is HTML.
  @integration_points %{"svg" => ~w(foreignobject desc title), "math" => ~w(mi mo mn ms mtext)}
  # Browsers stop nesting elements at about this depth, and it bounds the
  # tracked elements on a page of nothing but nested ones.
  @max_open 512
  @whitespace [?\t, ?\n, ?\f, ?\r, ?\s]
  # Rewritten pieces are handed to the sink in batches, so a page with millions
  # of links isn't held in memory as millions of pieces.
  @batch_size 1024

  def run(path, content) do
    if mode = mode(path) do
      content
      |> add_elixir_org_link()
      |> rewrite_tags(mode, [], &[&1 | &2])
      |> IO.iodata_to_binary()
    else
      content
    end
  end

  def rewrite_files(dir, files) do
    for path <- files, mode = mode(path) do
      full_path = Path.join(dir, path)
      content = full_path |> File.read!() |> add_elixir_org_link()

      File.open!(full_path, [:write, :raw, :binary, :delayed_write], fn file ->
        rewrite_tags(content, mode, file, fn file, data ->
          :ok = IO.binwrite(file, data)
          file
        end)
      end)
    end

    :ok
  end

  defp mode(path) do
    case MIME.from_path(path) do
      "text/html" -> :html
      "application/xhtml+xml" -> :xml
      _other -> nil
    end
  end

  defp add_elixir_org_link(content) do
    if String.contains?(content, @link_addition) do
      content
    else
      String.replace(content, @link_hooks, &(&1 <> " for the " <> @link_addition))
    end
  end

  # One pass over the page that finds tags the way a browser's tokenizer does:
  # it skips comments, doctypes, CDATA sections in SVG, MathML and XHTML, and
  # the content of HTML's raw text elements, reads attributes quoted,
  # single-quoted or unquoted with any case, and takes the first of a repeated
  # attribute. On the tags it finds it
  #
  #   * adds the analytics snippet before the first `</head>`,
  #   * removes `<link>` tags with a canonical rel, because the docs CDN sets
  #     `Link: rel="canonical"` on every page it serves, pointing at the same
  #     page under the package's unversioned subdomain, and a tag in the markup
  #     would be a second answer of the author's choosing,
  #   * adds `rel="nofollow"` to links that leave the official domains.
  #
  # Every other byte is copied as it is.
  defp rewrite_tags(content, mode, sink, write) do
    state = %{
      content: content,
      mode: mode,
      from: 0,
      pieces: [],
      count: 0,
      head?: false,
      open: [],
      open_depth: 0,
      open_names: %{},
      sink: sink,
      write: write
    }

    state
    |> scan(0)
    |> copy_until(byte_size(content))
    |> flush()
    |> Map.fetch!(:sink)
  end

  defp scan(%{content: content} = state, pos) do
    case :binary.match(content, "<", scope: {pos, byte_size(content) - pos}) do
      {lt, 1} -> markup(state, lt)
      :nomatch -> state
    end
  end

  defp markup(%{content: content} = state, lt) do
    case binary_part(content, lt + 1, byte_size(content) - lt - 1) do
      "!--" <> _ ->
        comment(state, lt + 4)

      "![CDATA[" <> _ ->
        if cdata?(state), do: cdata(state, lt + 9), else: bogus_comment(state, lt + 1)

      "!DOCTYPE" <> _ when state.mode == :xml ->
        xml_doctype(state, lt + 9)

      "?" <> _ when state.mode == :xml ->
        processing_instruction(state, lt + 2)

      "/>" <> _ ->
        scan(state, lt + 3)

      <<?/, c, _::binary>> when c in ?a..?z or c in ?A..?Z ->
        end_tag(state, lt)

      <<c, _::binary>> when c in [?!, ?/, ??] ->
        bogus_comment(state, lt + 1)

      <<c, _::binary>> when c in ?a..?z or c in ?A..?Z ->
        start_tag(state, lt)

      _ ->
        scan(state, lt + 1)
    end
  end

  # An XML comment ends only at `-->`.
  defp comment(%{content: content, mode: mode} = state, pos) do
    ends = if mode == :xml, do: ["-->"], else: ["-->", "--!>"]

    case binary_part(content, pos, byte_size(content) - pos) do
      ">" <> _ when mode == :html ->
        scan(state, pos + 1)

      "->" <> _ when mode == :html ->
        scan(state, pos + 2)

      _ ->
        case :binary.match(content, ends, scope: {pos, byte_size(content) - pos}) do
          {at, length} -> scan(state, at + length)
          :nomatch -> state
        end
    end
  end

  defp processing_instruction(%{content: content} = state, pos) do
    case :binary.match(content, "?>", scope: {pos, byte_size(content) - pos}) do
      {at, 2} -> scan(state, at + 2)
      :nomatch -> state
    end
  end

  # CDATA sections exist in XML and directly inside SVG and MathML elements. In
  # an integration point, and in the HTML inside one, a <![CDATA[ is a bogus
  # comment.
  defp cdata?(%{mode: :xml}), do: true
  defp cdata?(state), do: match?({:foreign, _root}, context(state.open))

  defp cdata(%{content: content} = state, pos) do
    case :binary.match(content, "]]>", scope: {pos, byte_size(content) - pos}) do
      {at, 3} -> scan(state, at + 3)
      :nomatch -> state
    end
  end

  # An XML doctype ends at the first `>` outside quotes and outside its internal
  # subset, whose declarations can hold quoted `>` and comments.
  defp xml_doctype(%{content: content} = state, pos) do
    case :binary.match(content, [">", "[", "\"", "'"], scope: {pos, byte_size(content) - pos}) do
      {at, 1} ->
        case :binary.at(content, at) do
          ?> -> scan(state, at + 1)
          ?[ -> internal_subset(state, at + 1)
          quote -> after_quote(state, at, quote, &xml_doctype/2)
        end

      :nomatch ->
        state
    end
  end

  defp internal_subset(%{content: content} = state, pos) do
    case :binary.match(content, ["]", "\"", "'", "<!--"], scope: {pos, byte_size(content) - pos}) do
      {at, 4} ->
        case :binary.match(content, "-->", scope: {at + 4, byte_size(content) - at - 4}) do
          {stop, 3} -> internal_subset(state, stop + 3)
          :nomatch -> state
        end

      {at, 1} ->
        case :binary.at(content, at) do
          ?] -> xml_doctype(state, at + 1)
          quote -> after_quote(state, at, quote, &internal_subset/2)
        end

      :nomatch ->
        state
    end
  end

  defp after_quote(%{content: content} = state, at, quote, continue) do
    case :binary.match(content, <<quote>>, scope: {at + 1, byte_size(content) - at - 1}) do
      {stop, 1} -> continue.(state, stop + 1)
      :nomatch -> state
    end
  end

  defp bogus_comment(%{content: content} = state, pos) do
    case :binary.match(content, ">", scope: {pos, byte_size(content) - pos}) do
      {at, 1} -> scan(state, at + 1)
      :nomatch -> state
    end
  end

  defp end_tag(%{content: content} = state, lt) do
    name_end = name_end(content, lt + 2)
    name = tag_name(content, lt + 2, name_end)

    case attributes(content, name_end, []) do
      {:ok, _attributes, tag_end, _self_closing?} ->
        state = close_element(state, name)

        if name == "head" and not state.head? do
          state
          |> copy_until(lt)
          |> put(analytics(state.mode))
          |> Map.put(:head?, true)
          |> scan(tag_end)
        else
          scan(state, tag_end)
        end

      :eof ->
        state
    end
  end

  defp start_tag(%{content: content} = state, lt) do
    name_end = name_end(content, lt + 1)
    name = tag_name(content, lt + 1, name_end)

    case attributes(content, name_end, []) do
      {:ok, attributes, tag_end, self_closing?} ->
        state
        |> rewrite_tag(name, attributes, lt, name_end, tag_end)
        |> open_element(name, attributes, self_closing?, tag_end)

      :eof ->
        state
    end
  end

  # XHTML is XML, where no element holds raw text.
  defp open_element(%{mode: :xml} = state, _name, _attributes, _self_closing?, tag_end) do
    scan(state, tag_end)
  end

  # Only SVG and MathML roots and the integration points inside them are
  # tracked, since they decide whether the content of an element named like a
  # raw text element is text or markup.
  defp open_element(state, name, attributes, self_closing?, tag_end) do
    case context(state.open) do
      {:foreign, root} ->
        cond do
          breakout?(name, attributes) ->
            state
            |> pop_open(fn {kind, _name} -> kind == :foreign end)
            |> scan(tag_end)

          not self_closing? and integration_point?(state.content, root, name, attributes) ->
            state
            |> push_open({:integration, name})
            |> scan(tag_end)

          true ->
            scan(state, tag_end)
        end

      :html ->
        cond do
          name in ["svg", "math"] and not self_closing? ->
            state
            |> push_open({:foreign, name})
            |> scan(tag_end)

          name == "plaintext" ->
            state

          name == "script" ->
            skip_script(state, tag_end, :data)

          name in @raw_text_elements ->
            skip_raw_text(state, name, tag_end)

          true ->
            scan(state, tag_end)
        end
    end
  end

  defp integration_point?(content, "math", "annotation-xml", attributes) do
    encoding = attribute_value(content, attributes, "encoding") || ""
    encoding = encoding |> decode_references() |> String.downcase(:ascii)
    encoding in ["text/html", "application/xhtml+xml"]
  end

  defp integration_point?(_content, root, name, _attributes),
    do: name in @integration_points[root]

  # A <font> breaks out only when it has one of these attributes.
  defp breakout?("font", attributes) do
    Enum.any?(attributes, fn {name, _name_end, _value} -> name in ["color", "face", "size"] end)
  end

  defp breakout?(name, _attributes), do: name in @breakout_tags

  defp escape_xml("&"), do: "&amp;"
  defp escape_xml("<"), do: "&lt;"
  defp escape_xml("\""), do: "&quot;"

  defp close_element(%{mode: :xml} = state, _name), do: state

  # Closes the innermost open element with this name and everything inside it.
  # A </p> or </br> inside SVG or MathML closes every open SVG and MathML
  # element, as the breakout start tags do.
  defp close_element(state, name) do
    cond do
      name in ["p", "br"] and match?({:foreign, _root}, context(state.open)) ->
        pop_open(state, fn {kind, _name} -> kind == :foreign end)

      Map.get(state.open_names, name, 0) > 0 ->
        state
        |> pop_open(fn {_kind, open_name} -> open_name != name end)
        |> pop_open(1)

      true ->
        state
    end
  end

  defp push_open(%{open_depth: depth} = state, _element) when depth >= @max_open, do: state

  defp push_open(state, {_kind, name} = element) do
    %{
      state
      | open: [element | state.open],
        open_depth: state.open_depth + 1,
        open_names: Map.update(state.open_names, name, 1, &(&1 + 1))
    }
  end

  # Pops open elements while `fun` returns true for them, or a given count.
  defp pop_open(%{open: [{_kind, name} = element | rest]} = state, fun)
       when is_function(fun, 1) do
    if fun.(element), do: state |> drop_open(name, rest) |> pop_open(fun), else: state
  end

  defp pop_open(%{open: [{_kind, name} | rest]} = state, count)
       when is_integer(count) and count > 0 do
    state |> drop_open(name, rest) |> pop_open(count - 1)
  end

  defp pop_open(state, _fun_or_count), do: state

  defp drop_open(state, name, rest) do
    %{
      state
      | open: rest,
        open_depth: state.open_depth - 1,
        open_names: Map.update!(state.open_names, name, &(&1 - 1))
    }
  end

  defp context([{:foreign, root} | _]), do: {:foreign, root}
  defp context(_open), do: :html

  defp rewrite_tag(%{content: content} = state, "link", attributes, lt, _name_end, tag_end) do
    cond do
      "canonical" not in rel_tokens(content, attributes) ->
        state

      # Removing an XML element would leave its end tag behind, so the
      # canonical keyword is taken out of its rel instead.
      state.mode == :xml ->
        {"rel", _rel_name_end, {_start, _stop, region_start, region_end}} =
          List.keyfind(attributes, "rel", 0)

        rel =
          rel_tokens(content, attributes)
          |> Enum.reject(&(&1 == "canonical"))
          |> Enum.join(" ")
          |> String.replace(["&", "<", "\""], &escape_xml/1)

        state
        |> copy_until(region_start)
        |> put([?", rel, ?"])
        |> Map.put(:from, region_end)

      true ->
        state
        |> copy_until(lt)
        |> Map.put(:from, skip_whitespace(content, tag_end))
    end
  end

  defp rewrite_tag(%{content: content} = state, "a", attributes, _lt, name_end, _tag_end) do
    case attribute_value(content, attributes, "href") do
      nil -> state
      href -> if followable?(href), do: state, else: add_nofollow(state, attributes, name_end)
    end
  end

  defp rewrite_tag(state, _name, _attributes, _lt, _name_end, _tag_end), do: state

  defp add_nofollow(%{content: content} = state, attributes, name_end) do
    case List.keyfind(attributes, "rel", 0) do
      nil ->
        state
        |> copy_until(name_end)
        |> put(~s| rel="nofollow"|)

      {"rel", rel_name_end, nil} ->
        state
        |> copy_until(rel_name_end)
        |> put(~s|="nofollow"|)

      {"rel", _rel_name_end, {value_start, value_end, region_start, region_end}} ->
        value = binary_part(content, value_start, value_end - value_start)

        cond do
          "nofollow" in tokens(value) ->
            state

          tokens(value) == [] ->
            state
            |> copy_until(region_start)
            |> put(~s|"nofollow"|)
            |> Map.put(:from, region_end)

          true ->
            state
            |> copy_until(region_start)
            |> put([?", String.replace(value, "\"", "&quot;"), " nofollow", ?"])
            |> Map.put(:from, region_end)
        end
    end
  end

  # A link is followed when it stays on the page's own host or goes to an
  # official domain. Anything that may name another host, written in any form
  # a browser accepts, is not, and neither is an href with character references,
  # which this doesn't decode.
  defp followable?(href) do
    url =
      href
      |> String.replace(["\t", "\n", "\r"], "")
      |> trim_leading_c0()
      |> String.replace("\\", "/")

    cond do
      String.contains?(url, "&") -> false
      String.starts_with?(url, "//") -> official?("https:" <> url)
      url =~ ~r/\A[A-Za-z][A-Za-z0-9+.-]*:/ -> official?(url)
      true -> true
    end
  end

  defp official?(url) do
    uri = URI.parse(url)
    host = uri.host && String.downcase(uri.host, :ascii)

    String.downcase(uri.scheme || "", :ascii) in ["http", "https"] and host != nil and
      Enum.any?(@official_domains, &(host == &1 or String.ends_with?(host, "." <> &1)))
  end

  defp trim_leading_c0(<<c, rest::binary>>) when c <= 0x20, do: trim_leading_c0(rest)
  defp trim_leading_c0(value), do: value

  defp rel_tokens(content, attributes) do
    case attribute_value(content, attributes, "rel") do
      nil -> []
      rel -> tokens(rel)
    end
  end

  defp tokens(value) do
    value
    |> decode_references()
    |> String.downcase(:ascii)
    |> String.split(["\t", "\n", "\f", "\r", " "], trim: true)
  end

  # The character references that can spell a rel keyword or the whitespace
  # between keywords.
  defp decode_references(value) do
    Regex.replace(~r/&(?:#[xX]([0-9a-fA-F]+);?|#([0-9]+);?|(Tab|NewLine);)/, value, fn
      _, hex, "", "" -> codepoint(hex, 16, 6)
      _, "", decimal, "" -> codepoint(decimal, 10, 7)
      _, "", "", "Tab" -> "\t"
      _, "", "", "NewLine" -> "\n"
    end)
  end

  defp codepoint(digits, base, max_digits) do
    digits = String.trim_leading(digits, "0")

    with true <- byte_size(digits) <= max_digits,
         codepoint when codepoint in 1..0x10FFFF and codepoint not in 0xD800..0xDFFF <-
           String.to_integer("0" <> digits, base) do
      <<codepoint::utf8>>
    else
      _ -> "\uFFFD"
    end
  end

  defp attribute_value(content, attributes, name) do
    case List.keyfind(attributes, name, 0) do
      nil -> nil
      {^name, _name_end, nil} -> ""
      {^name, _name_end, {start, stop, _, _}} -> binary_part(content, start, stop - start)
    end
  end

  # Script content ends at the first `</script>` outside the escaped states
  # that a `<!--` and then a `<script>` inside it put the tokenizer in.
  defp skip_script(%{content: content} = state, pos, escape) do
    case :binary.match(content, ["<!--", "-->", "<"], scope: {pos, byte_size(content) - pos}) do
      {at, 4} ->
        after_dashes = skip_dashes(content, at + 4)

        cond do
          byte_at(content, after_dashes) == ?> -> skip_script(state, after_dashes + 1, :data)
          escape == :data -> skip_script(state, after_dashes, :escaped)
          true -> skip_script(state, after_dashes, escape)
        end

      {at, 3} ->
        skip_script(state, at + 3, :data)

      {at, 1} ->
        cond do
          script_tag?(content, at + 2) and byte_at(content, at + 1) == ?/ ->
            if escape == :double_escaped,
              do: skip_script(state, at + 8, :escaped),
              else: scan(state, at)

          script_tag?(content, at + 1) and escape == :escaped ->
            skip_script(state, at + 7, :double_escaped)

          true ->
            skip_script(state, at + 1, escape)
        end

      :nomatch ->
        state
    end
  end

  defp script_tag?(content, pos) do
    pos + 6 <= byte_size(content) and tag_name(content, pos, pos + 6) == "script" and
      byte_at(content, pos + 6) in [?/, ?> | @whitespace]
  end

  defp skip_dashes(content, pos) do
    if byte_at(content, pos) == ?-, do: skip_dashes(content, pos + 1), else: pos
  end

  defp skip_raw_text(%{content: content} = state, name, pos) do
    case :binary.match(content, "</", scope: {pos, byte_size(content) - pos}) do
      {at, 2} ->
        name_end = at + 2 + byte_size(name)

        if name_end <= byte_size(content) and tag_name(content, at + 2, name_end) == name and
             byte_at(content, name_end) in [nil, ?/, ?> | @whitespace] do
          scan(state, at)
        else
          skip_raw_text(state, name, at + 2)
        end

      :nomatch ->
        state
    end
  end

  defp name_end(content, pos) do
    case byte_at(content, pos) do
      nil -> pos
      c when c in [?/, ?> | @whitespace] -> pos
      _ -> name_end(content, pos + 1)
    end
  end

  defp tag_name(content, start, stop) do
    content |> binary_part(start, stop - start) |> String.downcase(:ascii)
  end

  # The first of each attribute the rewriter reads (href, rel, encoding, and
  # color, face and size for <font>) as `{name, name_end, value}`, where the
  # value is nil for an attribute without one, or the value's bounds and the
  # bounds of the value with its quotes. Returns the position after the tag's
  # `>` and whether the tag ends in `/>`, or `:eof` for a tag the page ends
  # inside, which the browser drops.
  defp attributes(content, pos, acc) do
    case byte_at(content, pos) do
      nil -> :eof
      ?> -> {:ok, acc, pos + 1, false}
      ?/ when binary_part(content, pos + 1, 1) == ">" -> {:ok, acc, pos + 2, true}
      c when c in [?/ | @whitespace] -> attributes(content, pos + 1, acc)
      _ -> attribute_name(content, pos, pos + 1, acc)
    end
  end

  defp attribute_name(content, start, pos, acc) do
    case byte_at(content, pos) do
      nil ->
        :eof

      c when c in [?/, ?>, ?= | @whitespace] ->
        name = tag_name(content, start, pos)
        after_attribute_name(content, name, pos, skip_whitespace(content, pos), acc)

      _ ->
        attribute_name(content, start, pos + 1, acc)
    end
  end

  defp after_attribute_name(content, name, name_end, pos, acc) do
    case byte_at(content, pos) do
      ?= ->
        before_attribute_value(content, name, name_end, skip_whitespace(content, pos + 1), acc)

      _ ->
        attributes(content, pos, keep_attribute(acc, name, name_end, nil))
    end
  end

  defp before_attribute_value(content, name, name_end, pos, acc) do
    case byte_at(content, pos) do
      nil ->
        :eof

      ?> ->
        attributes(content, pos, keep_attribute(acc, name, name_end, nil))

      quote when quote in [?", ?'] ->
        case :binary.match(content, <<quote>>, scope: {pos + 1, byte_size(content) - pos - 1}) do
          {stop, 1} ->
            value = {pos + 1, stop, pos, stop + 1}
            attributes(content, stop + 1, keep_attribute(acc, name, name_end, value))

          :nomatch ->
            :eof
        end

      _ ->
        stop = unquoted_value_end(content, pos)
        attributes(content, stop, keep_attribute(acc, name, name_end, {pos, stop, pos, stop}))
    end
  end

  defp keep_attribute(acc, name, name_end, value)
       when name in ["href", "rel", "encoding", "color", "face", "size"] do
    if List.keymember?(acc, name, 0), do: acc, else: [{name, name_end, value} | acc]
  end

  defp keep_attribute(acc, _name, _name_end, _value), do: acc

  defp unquoted_value_end(content, pos) do
    case byte_at(content, pos) do
      c when c in [nil, ?> | @whitespace] -> pos
      _ -> unquoted_value_end(content, pos + 1)
    end
  end

  defp skip_whitespace(content, pos) do
    if byte_at(content, pos) in @whitespace, do: skip_whitespace(content, pos + 1), else: pos
  end

  defp byte_at(content, pos) when pos < byte_size(content), do: :binary.at(content, pos)
  defp byte_at(_content, _pos), do: nil

  defp analytics(mode) do
    host = Application.fetch_env!(:hexpm, :docs_url) |> URI.parse() |> Map.fetch!(:host)
    snippet = String.replace(@analytics_addition, "${DOMAIN}", host)

    # XML has no attributes without a value.
    if mode == :xml,
      do: String.replace(snippet, "<script async defer ", ~s|<script async="" defer="" |),
      else: snippet
  end

  defp copy_until(%{content: content, from: from} = state, pos) do
    state
    |> put(binary_part(content, from, pos - from))
    |> Map.put(:from, pos)
  end

  defp put(state, data) do
    state = %{state | pieces: [data | state.pieces], count: state.count + 1}
    if state.count >= @batch_size, do: flush(state), else: state
  end

  defp flush(%{pieces: pieces, sink: sink, write: write} = state) do
    %{state | pieces: [], count: 0, sink: write.(sink, Enum.reverse(pieces))}
  end
end

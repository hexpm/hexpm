defmodule Hexpm.Hexdocs.FileRewriter do
  @link_addition ~s|<a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|
  @link_hooks [
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" rel="noopener" title="@dignifiedquire">Friedel Ziegelmayer</a>|,
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  ]
  @analytics_addition "<script async defer src=\"https://s.${DOMAIN}/js/script.js\"></script><script>window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init({endpoint:\"https://s.${DOMAIN}/api/event\"})</script>"
  @official_domains ~w(hex.pm hexdocs.pm hexorgs.pm elixir-lang.org erlang.org)
  @html_types ~w(text/html application/xhtml+xml)
  # Elements whose content the browser reads as text up to their end tag.
  @raw_text_elements ~w(script style textarea title xmp iframe noembed noframes)
  @whitespace [?\t, ?\n, ?\f, ?\r, ?\s]
  # Rewritten pieces are handed to the sink in batches, so a page with millions
  # of links isn't held in memory as millions of pieces.
  @batch_size 1024

  def run(path, content) do
    if html?(path) do
      content
      |> add_elixir_org_link()
      |> rewrite_tags([], &[&1 | &2])
      |> IO.iodata_to_binary()
    else
      content
    end
  end

  def rewrite_files(dir, files) do
    for path <- files, html?(path) do
      full_path = Path.join(dir, path)
      content = full_path |> File.read!() |> add_elixir_org_link()

      File.open!(full_path, [:write, :raw, :binary, :delayed_write], fn file ->
        rewrite_tags(content, file, fn file, data ->
          :ok = IO.binwrite(file, data)
          file
        end)
      end)
    end

    :ok
  end

  defp html?(path), do: MIME.from_path(path) in @html_types

  defp add_elixir_org_link(content) do
    if String.contains?(content, @link_addition) do
      content
    else
      String.replace(content, @link_hooks, &(&1 <> " for the " <> @link_addition))
    end
  end

  # One pass over the page that finds tags the way a browser's tokenizer does:
  # it skips comments, doctypes and the content of raw text elements outside
  # SVG and MathML, reads attributes quoted, single-quoted or unquoted with any
  # case, and takes the first of a repeated attribute. On the tags it finds it
  #
  #   * adds the analytics snippet before the first `</head>`,
  #   * removes `<link>` tags with a canonical rel, because the docs CDN sets
  #     `Link: rel="canonical"` on every page it serves, pointing at the same
  #     page under the package's unversioned subdomain, and a tag in the markup
  #     would be a second answer of the author's choosing,
  #   * adds `rel="nofollow"` to links that leave the official domains.
  #
  # Every other byte is copied as it is.
  defp rewrite_tags(content, sink, write) do
    state = %{
      content: content,
      from: 0,
      pieces: [],
      count: 0,
      head?: false,
      foreign: 0,
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
      "!--" <> _ -> comment(state, lt + 4)
      "/>" <> _ -> scan(state, lt + 3)
      <<?/, c, _::binary>> when c in ?a..?z or c in ?A..?Z -> end_tag(state, lt)
      <<c, _::binary>> when c in [?!, ?/, ??] -> bogus_comment(state, lt + 1)
      <<c, _::binary>> when c in ?a..?z or c in ?A..?Z -> start_tag(state, lt)
      _ -> scan(state, lt + 1)
    end
  end

  defp comment(%{content: content} = state, pos) do
    case binary_part(content, pos, byte_size(content) - pos) do
      ">" <> _ ->
        scan(state, pos + 1)

      "->" <> _ ->
        scan(state, pos + 2)

      _ ->
        case :binary.match(content, ["-->", "--!>"], scope: {pos, byte_size(content) - pos}) do
          {at, length} -> scan(state, at + length)
          :nomatch -> state
        end
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
        cond do
          name == "head" and not state.head? ->
            state
            |> copy_until(lt)
            |> put(analytics())
            |> Map.put(:head?, true)
            |> scan(tag_end)

          name in ["svg", "math"] and state.foreign > 0 ->
            scan(%{state | foreign: state.foreign - 1}, tag_end)

          true ->
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
        state = rewrite_tag(state, name, attributes, lt, name_end, tag_end)

        # Inside SVG and MathML, script, style, title and the other raw text
        # names are ordinary elements holding markup, so raw text is only
        # skipped while no <svg> or <math> is open.
        cond do
          name in ["svg", "math"] and not self_closing? ->
            scan(%{state | foreign: state.foreign + 1}, tag_end)

          state.foreign > 0 ->
            scan(state, tag_end)

          name == "plaintext" ->
            state

          name in @raw_text_elements ->
            skip_raw_text(state, name, tag_end)

          true ->
            scan(state, tag_end)
        end

      :eof ->
        state
    end
  end

  defp rewrite_tag(%{content: content} = state, "link", attributes, lt, _name_end, tag_end) do
    if "canonical" in rel_tokens(content, attributes) do
      state
      |> copy_until(lt)
      |> Map.put(:from, skip_whitespace(content, tag_end))
    else
      state
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

  # The first `href` and `rel` attributes of a tag as `{name, name_end, value}`,
  # where the value is nil for an attribute without one, or the value's bounds
  # and the bounds of the value with its quotes. Returns the position after the
  # tag's `>` and whether the tag ends in `/>`, or `:eof` for a tag the page
  # ends inside, which the browser drops.
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

  defp keep_attribute(acc, name, name_end, value) when name in ["href", "rel"] do
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

  defp analytics() do
    host = Application.fetch_env!(:hexpm, :docs_url) |> URI.parse() |> Map.fetch!(:host)
    String.replace(@analytics_addition, "${DOMAIN}", host)
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

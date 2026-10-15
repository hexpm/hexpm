defmodule Hexpm.Hexdocs.FileRewriter do
  @link_addition ~s|<a href="https://elixir-lang.org" title="Elixir" target="_blank">Elixir programming language</a>|
  @link_hooks [
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" rel="noopener" title="@dignifiedquire">Friedel Ziegelmayer</a>|,
    ~s|<a href="https://twitter.com/dignifiedquire" target="_blank" title="@dignifiedquire">Friedel Ziegelmayer</a>|
  ]
  @analytics_addition "<script async defer src=\"https://s.${DOMAIN}/js/script.js\"></script><script>window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init({endpoint:\"https://s.${DOMAIN}/api/event\"})</script>"
  @official_domains ~w(hex.pm hexdocs.pm hexorgs.pm elixir-lang.org erlang.org)
  @whitespace [?\t, ?\n, ?\f, ?\r, ?\s]

  def run(path, content) do
    if html?(path) do
      content
      |> add_elixir_org_link()
      |> add_analytics()
      |> rewrite_tags()
    else
      content
    end
  end

  def rewrite_files(dir, files) do
    for path <- files, html?(path) do
      full_path = Path.join(dir, path)
      File.write!(full_path, run(path, File.read!(full_path)))
    end

    :ok
  end

  defp html?(path), do: MIME.from_path(path) == "text/html"

  defp add_elixir_org_link(content) do
    if String.contains?(content, @link_addition) do
      content
    else
      String.replace(content, @link_hooks, &(&1 <> " for the " <> @link_addition))
    end
  end

  defp add_analytics(content) do
    case :binary.match(content, "</head>") do
      {at, _length} ->
        host = Application.fetch_env!(:hexpm, :docs_url) |> URI.parse() |> Map.fetch!(:host)
        snippet = String.replace(@analytics_addition, "${DOMAIN}", host)
        rest = binary_part(content, at, byte_size(content) - at)
        <<binary_part(content, 0, at)::binary, snippet::binary, rest::binary>>

      :nomatch ->
        content
    end
  end

  # One pass over the page that reads `<a>` and `<link>` tags the way a browser
  # does, with attributes quoted, single-quoted or unquoted, in any case, and
  # the first of a repeated attribute taking effect. It removes `<link>` tags
  # with a canonical rel, because the docs CDN sets `Link: rel="canonical"` on
  # every page it serves, pointing at the same page under the package's
  # unversioned subdomain, and a tag in the markup would be a second answer of
  # the author's choosing. It adds `rel="nofollow"` to links that may leave the
  # official domains. Every other byte is copied as it is.
  defp rewrite_tags(content), do: scan(content, 0, 0, <<>>)

  defp scan(content, pos, from, acc) do
    case :binary.match(content, "<", scope: {pos, byte_size(content) - pos}) do
      {lt, 1} ->
        case tag_name(content, lt + 1) do
          nil ->
            scan(content, lt + 1, from, acc)

          name ->
            name_end = lt + 1 + byte_size(name)

            case attributes(content, name_end, []) do
              {:ok, attributes, tag_end} ->
                {from, acc} =
                  rewrite_tag(content, name, attributes, lt, name_end, tag_end, from, acc)

                scan(content, tag_end, from, acc)

              # The page ends inside the tag, which the browser drops.
              :eof ->
                finish(content, from, acc)
            end
        end

      :nomatch ->
        finish(content, from, acc)
    end
  end

  defp finish(content, from, acc), do: copy(content, from, byte_size(content), acc)

  defp copy(content, from, to, acc) do
    <<acc::binary, binary_part(content, from, to - from)::binary>>
  end

  defp rewrite_tag(content, "link", attributes, lt, _name_end, tag_end, from, acc) do
    if "canonical" in tokens(attribute_value(content, attributes, "rel")) do
      {skip_whitespace(content, tag_end), copy(content, from, lt, acc)}
    else
      {from, acc}
    end
  end

  defp rewrite_tag(content, "a", attributes, _lt, name_end, _tag_end, from, acc) do
    href = attribute_value(content, attributes, "href")

    if href == nil or followable?(href) do
      {from, acc}
    else
      add_nofollow(content, attributes, name_end, from, acc)
    end
  end

  defp add_nofollow(content, attributes, name_end, from, acc) do
    case List.keyfind(attributes, "rel", 0) do
      nil ->
        {name_end, <<copy(content, from, name_end, acc)::binary, ~s| rel="nofollow"|>>}

      {"rel", rel_name_end, nil} ->
        {rel_name_end, <<copy(content, from, rel_name_end, acc)::binary, ~s|="nofollow"|>>}

      {"rel", _rel_name_end, {value_start, value_end, region_start, region_end}} ->
        value = binary_part(content, value_start, value_end - value_start)

        cond do
          "nofollow" in tokens(value) ->
            {from, acc}

          tokens(value) == [] ->
            {region_end, <<copy(content, from, region_start, acc)::binary, ~s|"nofollow"|>>}

          true ->
            rel = ~s|"#{String.replace(value, "\"", "&quot;")} nofollow"|
            {region_end, <<copy(content, from, region_start, acc)::binary, rel::binary>>}
        end
    end
  end

  # A link is followed when it stays on the page's own host or goes to an
  # official domain. Anything that may name another host, written in any form a
  # browser accepts, is not, and neither is an href with character references,
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

  defp tokens(nil), do: []

  defp tokens(value) do
    value
    |> String.downcase(:ascii)
    |> String.split(["\t", "\n", "\f", "\r", " "], trim: true)
  end

  defp attribute_value(content, attributes, name) do
    case List.keyfind(attributes, name, 0) do
      nil -> nil
      {^name, _name_end, nil} -> ""
      {^name, _name_end, {start, stop, _, _}} -> binary_part(content, start, stop - start)
    end
  end

  # "a" or "link" when the tag starting at `pos` is one of them, in any case.
  defp tag_name(content, pos) do
    Enum.find(["a", "link"], fn name ->
      stop = pos + byte_size(name)

      stop <= byte_size(content) and
        String.downcase(binary_part(content, pos, byte_size(name)), :ascii) == name and
        byte_at(content, stop) in [nil, ?/, ?> | @whitespace]
    end)
  end

  # The first `href` and `rel` attributes of a tag as `{name, name_end, value}`,
  # where the value is nil for an attribute without one, or the value's bounds
  # and the bounds of the value with its quotes. Returns the position after the
  # tag's `>`, or `:eof` for a tag the page ends inside.
  defp attributes(content, pos, acc) do
    case byte_at(content, pos) do
      nil -> :eof
      ?> -> {:ok, acc, pos + 1}
      c when c in [?/ | @whitespace] -> attributes(content, pos + 1, acc)
      _ -> attribute_name(content, pos, pos + 1, acc)
    end
  end

  defp attribute_name(content, start, pos, acc) do
    case byte_at(content, pos) do
      nil ->
        :eof

      c when c in [?/, ?>, ?= | @whitespace] ->
        name = String.downcase(binary_part(content, start, pos - start), :ascii)
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
end

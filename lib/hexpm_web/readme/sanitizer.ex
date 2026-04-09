defmodule HexpmWeb.Readme.Sanitizer do
  @moduledoc """
  Floki-based allowlist sanitizer for README HTML.

  Strips unsafe tags and attributes to prevent XSS while preserving
  common markdown-rendered content.
  """

  @allowed_tags MapSet.new(~w(
    p h1 h2 h3 h4 h5 h6 blockquote pre code em strong del ins
    a img ul ol li table thead tbody tr th td br hr div span
    details summary input sup sub dl dt dd abbr kbd samp var
  ))

  @allowed_attributes %{
    "a" => MapSet.new(~w(href title)),
    "img" => MapSet.new(~w(src alt width height title)),
    "th" => MapSet.new(~w(align colspan rowspan)),
    "td" => MapSet.new(~w(align colspan rowspan)),
    "input" => MapSet.new(~w(type checked disabled)),
    "code" => MapSet.new(~w(class)),
    "div" => MapSet.new(~w(class)),
    "span" => MapSet.new(~w(class)),
    "h1" => MapSet.new(~w(id)),
    "h2" => MapSet.new(~w(id)),
    "h3" => MapSet.new(~w(id)),
    "h4" => MapSet.new(~w(id)),
    "h5" => MapSet.new(~w(id)),
    "h6" => MapSet.new(~w(id))
  }

  @safe_url_schemes MapSet.new(~w(http https mailto))

  @doc """
  Sanitizes HTML by stripping disallowed tags and attributes.
  """
  def sanitize(html) do
    html
    |> Floki.parse_document!()
    |> sanitize_nodes()
    |> Floki.raw_html()
  end

  defp sanitize_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &sanitize_node/1)
  end

  defp sanitize_node({:comment, _}), do: []
  defp sanitize_node({:pi, _, _}), do: []
  defp sanitize_node({:doctype, _, _, _}), do: []
  defp sanitize_node(text) when is_binary(text), do: [text]

  defp sanitize_node({"input", attrs, children}) do
    if checkbox_input?(attrs) do
      attrs = sanitize_attributes("input", attrs)
      children = sanitize_nodes(children)
      [{"input", attrs, children}]
    else
      sanitize_nodes(children)
    end
  end

  defp sanitize_node({tag, attrs, children}) do
    if MapSet.member?(@allowed_tags, tag) do
      attrs = sanitize_attributes(tag, attrs)
      children = sanitize_nodes(children)
      [{tag, attrs, children}]
    else
      sanitize_nodes(children)
    end
  end

  defp sanitize_attributes(tag, attrs) do
    allowed = Map.get(@allowed_attributes, tag, MapSet.new())

    attrs
    |> style_to_align(tag)
    |> Enum.filter(fn {name, _value} ->
      MapSet.member?(allowed, name) and not String.starts_with?(name, "on")
    end)
    |> Enum.flat_map(fn attr ->
      sanitize_attribute(tag, attr)
    end)
    |> maybe_add_link_attrs(tag)
  end

  defp sanitize_attribute(_tag, {"href", _value} = attr), do: sanitize_url_attr(attr)
  defp sanitize_attribute(_tag, {"src", _value} = attr), do: sanitize_url_attr(attr)

  defp sanitize_attribute(tag, {"id", value}) when tag in ~w(h1 h2 h3 h4 h5 h6) do
    [{"id", "user-content-" <> value}]
  end

  defp sanitize_attribute(_tag, attr), do: [attr]

  # Convert style="text-align: X" to align="X" to avoid CSP style-src violations
  defp style_to_align(attrs, tag) when tag in ~w(th td) do
    case Enum.find(attrs, fn {name, _} -> name == "style" end) do
      {"style", value} ->
        case Regex.run(~r/text-align\s*:\s*(left|right|center|justify)/i, value) do
          [_, alignment] ->
            attrs = Enum.reject(attrs, fn {name, _} -> name == "style" end)
            [{"align", String.downcase(alignment)} | attrs]

          nil ->
            attrs
        end

      nil ->
        attrs
    end
  end

  defp style_to_align(attrs, _tag), do: attrs

  defp sanitize_url_attr({name, value}) do
    # Strip ASCII control characters and whitespace that WHATWG URL parsing
    # would ignore but RFC 3986 (Elixir's URI) would not. This prevents
    # bypasses like "java\tscript:alert(1)" where URI.parse sees no scheme
    # but browsers strip the tab and execute javascript:.
    normalized = String.replace(value, ~r/[\x00-\x1f\x7f]/, "")

    uri = URI.parse(String.trim(normalized))

    cond do
      uri.scheme == nil ->
        [{name, value}]

      MapSet.member?(@safe_url_schemes, String.downcase(uri.scheme)) ->
        [{name, value}]

      true ->
        []
    end
  end

  defp checkbox_input?(attrs) do
    Enum.any?(attrs, fn {name, value} ->
      name == "type" and String.downcase(value) == "checkbox"
    end)
  end

  defp maybe_add_link_attrs(attrs, "a") do
    attrs ++ [{"rel", "nofollow noopener"}, {"target", "_blank"}]
  end

  defp maybe_add_link_attrs(attrs, _tag), do: attrs
end

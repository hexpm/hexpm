defmodule HexpmWeb.MarkdownEngine do
  @behaviour Phoenix.Template.Engine

  import Earmark.AstTools, only: [find_att_in_node: 2, merge_atts: 2]

  # Placeholder that will be replaced with the actual nonce at runtime
  @nonce_placeholder "%%SCRIPT_NONCE%%"

  @supported_languages %{
    "elixir" => Makeup.Lexers.ElixirLexer,
    "erlang" => Makeup.Lexers.ErlangLexer,
    "gleam" => Makeup.Lexers.GleamLexer
  }

  @header_tags ["h3", "h4"]

  def compile(path, _name) do
    html =
      path
      |> File.read!()
      |> Earmark.as_ast!(gfm: true)
      |> Earmark.Transform.map_ast(&transform_node/1, true)
      |> Earmark.transform()

    # Generate code that replaces placeholder with actual nonce at runtime
    quote do
      nonce = var!(assigns)[:script_src_nonce] || ""

      unquote(html)
      |> String.replace(unquote(@nonce_placeholder), nonce)
      |> Phoenix.HTML.raw()
    end
  end

  defp transform_node({tag, _attrs, children, meta}) when tag in @header_tags do
    header_text = children |> extract_text() |> String.downcase()

    anchor =
      header_text
      |> String.replace(" ", "-")
      |> String.replace(~r"([^a-zA-Z0-9\-])", "")

    icon_html =
      HexpmWeb.ViewIcons.icon(:heroicon, :link, class: "icon-link")
      |> Phoenix.HTML.safe_to_string()

    icon = {"span", [], [icon_html], %{verbatim: true}}
    link = {"a", [{"href", "##{anchor}"}, {"class", "hover-link"}], [icon], %{}}

    {:replace,
     {tag, [{"id", anchor}, {"class", "section-heading"}], [link, " " | children], meta}}
  end

  defp transform_node(
         {"pre", _pre_attrs, [{"code", code_attrs, children, _code_meta}], _pre_meta}
       ) do
    language = find_att_in_node(code_attrs, "class")

    case language && Map.get(@supported_languages, language) do
      nil ->
        {"pre", [], nil, %{}}

      lexer ->
        code = extract_text(children)
        inner_html = Makeup.highlight_inner_html(code, lexer: lexer)

        {:replace,
         {"pre", [{"class", "highlight"}], [{"code", [], [inner_html], %{verbatim: true}}], %{}}}
    end
  end

  defp transform_node({"script", attrs, children, meta}) do
    if find_att_in_node(attrs, "nonce") do
      {"script", attrs, nil, meta}
    else
      {:replace, {"script", [{"nonce", @nonce_placeholder} | attrs], children, meta}}
    end
  end

  defp transform_node({tag, attrs, _children, meta}) when tag in ["th", "td"] do
    case find_att_in_node(attrs, "style") do
      "text-align: " <> align ->
        new_attrs =
          attrs
          |> List.keydelete("style", 0)
          |> merge_atts(class: "text-#{String.trim_trailing(align, ";")}")

        {tag, new_attrs, nil, meta}

      _ ->
        {tag, attrs, nil, meta}
    end
  end

  defp transform_node(node), do: node

  defp extract_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, &extract_text/1)
  end

  defp extract_text({_tag, _attrs, children, _meta}), do: extract_text(children)
  defp extract_text(text) when is_binary(text), do: text
end

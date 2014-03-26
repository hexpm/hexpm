defmodule HexWeb.Web.HTMLEngine do
  use EEx.TransformerEngine
  use EEx.AssignsEngine

  def handle_text(buffer, text) do
    quote do
      { :safe, unquote(buffer) <> unquote(text) }
    end
  end

  def handle_expr(buffer, "=", expr) do
    expr   = transform(expr)
    buffer = unsafe(buffer)

    quote location: :keep do
      tmp = unquote(buffer)
      case unquote(expr) do
        { :safe, value } ->
          tmp <> to_string(value)
        value ->
          tmp <> HexWeb.Web.HTMLEngine.escape(to_string(value))
      end
    end
  end

  def handle_expr(buffer, "", expr) do
    quote do
      tmp = unquote(buffer)
      unquote(expr)
      tmp
    end
  end

  defp unsafe({ :safe, value }), do: value
  defp unsafe(value), do: value

  @escapes [{ ?<, "&lt;" }, { ?>, "&gt;" }, { ?&, "&amp;" }, { ?", "&quot;" }, { ?', "&#39;" }]

  def escape(buffer) do
    iolist_to_binary(do_escape(buffer))
  end

  Enum.each(@escapes, fn { match, insert } ->
    defp do_escape(<< unquote(match) :: utf8, rest :: binary >>) do
      [ unquote(insert) | do_escape(rest) ]
    end
  end)

  defp do_escape(<< char :: utf8, rest :: binary >>),
    do: [ char | do_escape(rest) ]
  defp do_escape(""),
    do: []
end

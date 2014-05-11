defmodule HexWeb.Web.HTML do
  alias HexWeb.Web.HTML

  defprotocol Safe do
    def to_string(thing)
  end

  defimpl Safe, for: Atom do
    def to_string(nil), do: ""
    def to_string(atom), do: HTML.escape(atom_to_binary(atom))
  end

  defimpl Safe, for: BitString do
    def to_string(thing) when is_binary(thing) do
      HTML.escape(thing)
    end
  end

  defimpl Safe, for: List do
    def to_string(list) do
      for thing <- list, into: "", do: << Safe.to_string(thing) :: binary >>
    end
  end

  defimpl Safe, for: Integer do
    def to_string(thing), do: integer_to_binary(thing)
  end

  defimpl Safe, for: Float do
    def to_string(thing) do
      iodata_to_binary(:io_lib_format.fwrite_g(thing))
    end
  end

  defimpl Safe, for: Tuple do
    def to_string({ :safe, thing }), do: Kernel.to_string(thing)
  end

  defmodule Engine do
    use EEx.TransformerEngine
    use EEx.AssignsEngine

    def handle_body(body), do: unsafe(body)

    def handle_text(buffer, text) do
      quote do
        { :safe, unquote(buffer) <> unquote(text) }
      end
    end

    def handle_expr(buffer, "=", expr) do
      expr   = transform(expr)
      buffer = unsafe(buffer)

      quote do
        tmp = unquote(buffer)
        tmp <> Safe.to_string(unquote(expr))
      end
    end

    def handle_expr(buffer, "", expr) do
      expr   = transform(expr)
      buffer = unsafe(buffer)

      quote do
        tmp = unquote(buffer)
        unquote(expr)
        tmp
      end
    end

    defp unsafe({ :safe, value }), do: value
    defp unsafe(value), do: value
  end

  @escapes [{ ?<, "&lt;" }, { ?>, "&gt;" }, { ?&, "&amp;" }, { ?", "&quot;" }, { ?', "&#39;" }]

  def escape(buffer) do
    for << char <- buffer >>, into: "" do
      << escape_char(char) :: binary >>
    end
  end

  Enum.each(@escapes, fn { match, insert } ->
    defp escape_char(unquote(match)), do: unquote(insert)
  end)

  defp escape_char(char), do: << char >>
end

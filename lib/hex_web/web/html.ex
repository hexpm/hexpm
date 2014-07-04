defmodule HexWeb.Web.HTML do
  alias HexWeb.Web.HTML

  defprotocol Safe do
    def to_string(thing)
  end

  defimpl Safe, for: Atom do
    def to_string(nil), do: ""
    def to_string(atom), do: HTML.escape(Atom.to_binary(atom))
  end

  defimpl Safe, for: BitString do
    def to_string(thing) when is_binary(thing) do
      HTML.escape(thing)
    end
  end

  defimpl Safe, for: List do
    def to_string(list) do
      do_to_string(list) |> IO.iodata_to_binary
    end

    defp do_to_string([h|t]) do
      [do_to_string(h)|do_to_string(t)]
    end

    defp do_to_string([]) do
      []
    end

    # We could inline the escape for integers ?>, ?<, ?&, ?" and ?'
    # instead of calling Html.escape/1
    defp do_to_string(h) when is_integer(h) do
      Html.escape(<<h :: utf8>>)
    end

    defp do_to_string(h) when is_binary(h) do
      Html.escape(h)
    end

    defp do_to_string({:safe, h}) when is_binary(h) do
      h
    end
  end

  defimpl Safe, for: Integer do
    def to_string(thing), do: Integer.to_string(thing)
  end

  defimpl Safe, for: Float do
    def to_string(thing) do
      IO.iodata_to_binary(:io_lib_format.fwrite_g(thing))
    end
  end

  defimpl Safe, for: Tuple do
    def to_string({:safe, data}) when is_binary(data), do: data
  end

  defmodule Engine do
    use EEx.TransformerEngine
    use EEx.AssignsEngine

    def handle_body(body), do: unsafe(body)

    def handle_text(buffer, text) do
      quote do
        {:safe, unquote(unsafe(buffer)) <> unquote(text)}
      end
    end

    def handle_expr(buffer, "=", expr) do
      expr   = transform(expr)
      buffer = unsafe(buffer)

      {:safe, quote do
        tmp = unquote(buffer)
        tmp <> (case unquote(expr) do
          {:safe, bin} when is_binary(bin) -> bin
          bin when is_binary(bin) -> HTML.escape(bin)
          other -> Safe.to_string(other)
        end)
      end}
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

    defp unsafe({:safe, value}), do: value
    defp unsafe(value), do: value
  end

  @escapes [{?<, "&lt;"}, {?>, "&gt;"}, {?&, "&amp;"}, {?", "&quot;"}, {?', "&#39;"}]

  def escape(buffer) do
    IO.iodata_to_binary(for <<char <- buffer>>, do: escape_char(char))
  end

  @compile {:inline, escape_char: 1}

  Enum.each(@escapes, fn {match, insert} ->
    defp escape_char(unquote(match)), do: unquote(insert)
  end)

  defp escape_char(char), do: << char >>
end

defmodule HexWeb.Web.HTML do
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

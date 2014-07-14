alias HexWeb.Web.HTML
alias HexWeb.Web.HTML.Safe

defprotocol HexWeb.Web.HTML.Safe do
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

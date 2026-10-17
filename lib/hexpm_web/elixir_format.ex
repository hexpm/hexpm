defmodule HexpmWeb.ElixirFormat do
  def encode_to_iodata!(term) do
    term
    |> Hexpm.Utils.binarify()
    |> inspect(limit: :infinity, binaries: :as_strings)
  end
end

defmodule HexWeb.API.ConsultFormat do
  def encode(map) when is_map(map) do
    map
    |> HexWeb.Util.binarify
    |> Enum.map(&[:io_lib.print(&1) | ".\n\n"])
    |> IO.iodata_to_binary
  end

  def decode(string) when is_binary(string) do
    {:ok, pid} = StringIO.open(string)
    try do
      consult(pid, [])
    after
      StringIO.close(pid)
    end
  end

  defp consult(pid, acc) when is_pid(pid) do
    case :io.read(pid, '') do
      {:ok, term}      -> consult(pid, [term|acc])
      {:error, reason} -> {:error, reason}
      :eof             -> {:ok, Enum.into(acc, %{})}
    end
  end
end

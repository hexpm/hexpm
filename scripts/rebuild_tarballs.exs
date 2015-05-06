defmodule HexWeb.Scripts.Tarballs do
  @temp_tar "temp.tar.gz"

  # NOTE: Remember to update checksums in releases table with new checksums

  def main([input_dir]) do
    all_tars = Path.wildcard(Path.join(input_dir, "*.tar"))
    map = %{mix: HashSet.new, rebar: HashSet.new, make: HashSet.new, unknown: HashSet.new}

    Enum.reduce(all_tars, map, fn filename, map ->
      tarname = Path.basename(filename)
      [package, _] = String.split(tarname, "-", parts: 2)

      {:ok, files} = :erl_tar.extract(String.to_char_list(filename), [:memory])
      files = convert_files(files)

      content_files = contents(files)

      cond do
        "mix.exs" in content_files ->
          type = :mix
        "rebar.config" in content_files or "rebar" in content_files ->
          type = :rebar
        "Makefile" in content_files ->
          type = :make
        true ->
          type = :unknown
      end

      Map.update!(map, type, &HashSet.put(&1, package))
    end)
    |> Enum.map(fn {k, v} -> {k, Enum.sort(v)} end)
    |> IO.inspect(limit: -1)
    |> Enum.map(fn {k, v} -> {k, Enum.count(v)} end)
    |> IO.inspect
  end

  defp contents(files) do
    {:ok, inner_files} = :erl_tar.extract({:binary, files["contents.tar.gz"]}, [:memory, :compressed])
    convert_files(inner_files)
    |> Enum.map(&elem(&1, 0))
  end

  defp convert_files(files) do
    Enum.into(files, %{}, fn {name, binary} ->
      {List.to_string(name), binary}
    end)
  end
end

HexWeb.Scripts.Tarballs.main(System.argv)

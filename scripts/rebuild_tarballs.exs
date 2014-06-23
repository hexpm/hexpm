defmodule HexWeb.Scripts.Tarballs do
  @temp_tar "temp.tar.gz"

  # NOTE: Remember to update checksums in releases table with new checksums

  def main([input_dir, output_dir]) do
    all_tars = Path.wildcard(Path.join(input_dir, "*.tar"))

    Enum.each(all_tars, fn filename ->
      tarname = Path.basename(filename)
      IO.puts tarname

      {:ok, files} = :erl_tar.extract(String.to_char_list(filename), [:memory])
      files = convert_files(files)

      content_files = contents(files)

      files = %{
        "VERSION" => "2",
        "CHECKSUM" => nil,
        "metadata.exs" => meta(files, content_files),
        "contents.tar.gz" => File.read!(@temp_tar) }

      files = %{files | "CHECKSUM" => checksum(files)}
              |> Enum.into([], fn {name, content} -> {String.to_char_list(name), content} end)

      File.rm!(@temp_tar)
      output = Path.join(output_dir, tarname)
      :erl_tar.create(output, files)
    end)
  end

  defp meta(files, content_files) do
    {:ok, meta} = HexWeb.API.ElixirFormat.decode(files["metadata.exs"])

    reqs = Enum.into(meta["requirements"], %{}, fn
      {name, req} when is_binary(req) ->
        {name, %{"requirement" => req, "optional" => nil}}
      {name, map} when is_map(map) ->
        {name, map}
    end)

    meta = %{meta | "requirements" => reqs, "files" => content_files}
    HexWeb.API.ElixirFormat.encode(meta)
  end

  defp contents(files) do
    {:ok, inner_files} = :erl_tar.extract({:binary, files["contents.tar.gz"]}, [:memory, :compressed])
    inner_files = uniq(inner_files)

    :erl_tar.create(@temp_tar, inner_files, [:compressed])

    Enum.map(inner_files, &List.to_string(elem(&1, 0)))
  end

  defp checksum(files) do
    blob = files["VERSION"] <> files["metadata.exs"] <> files["contents.tar.gz"]
    :crypto.hash(:sha256, blob)
    |> Base.encode16
  end

  defp uniq(files) do
    Enum.uniq(files, &elem(&1, 0))
  end

  defp convert_files(files) do
    Enum.into(files, %{}, fn {name, binary} ->
      {List.to_string(name), binary}
    end)
  end
end

HexWeb.Scripts.Tarballs.main(System.argv)

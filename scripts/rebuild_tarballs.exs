defmodule HexWeb.Scripts.Tarballs do
  # NOTE: Remember to update checksums in releases table with new checksums

  @tools [
    {"mix.exs",       "mix"},
    {"rebar",         "rebar"},
    {"rebar.config",  "rebar"},
    {"Makefile",     "make"},
    {"Makefile.win",  "make"},
  ]

  def main([]) do
    all_tars = Path.wildcard(Path.join("tarballs", "*.tar"))
    File.mkdir_p!("tarballs2")

    Enum.each(all_tars, fn filename ->
      tarname = Path.basename(filename)
      [_, package, release] = Regex.run(~r"(.*)-(.*).tar"U, tarname)

      {:ok, files} = :erl_tar.extract(String.to_char_list(filename), [:memory])
      files = string_files(files)
      content_files = contents(files)
      tools = tools(@tools, content_files)

      checksum = update_tarball(package, release, files, tools)
      put_info(package, release, tools, checksum)
    end)
  end

  defp put_info(package, release, tools, checksum) do
    tools = Enum.join(tools, ",")
    Enum.join([package, release, tools, checksum], ";")
    |> IO.puts
  end

  defp update_tarball(package, release, files, tools) do
    {:ok, metadata} = files["metadata.config"] |> HexWeb.API.ConsultFormat.decode
    metadata = put_in(metadata["build_tools"], tools)
    metadata = HexWeb.API.ConsultFormat.encode(metadata)
    files = put_in(files["metadata.config"], metadata)

    blob = files["VERSION"] <> metadata <> files["contents.tar.gz"]
    checksum = :crypto.hash(:sha256, blob) |> Base.encode16
    files = put_in(files["CHECKSUM"], checksum)

    path = Path.join("tarballs2", "#{package}-#{release}.tar")
    files = list_files(files)
    :ok = :erl_tar.create(path, files)

    checksum
  end

  defp tools(tools, files) do
    files = MapSet.new(files)

    Enum.reduce(tools, MapSet.new, fn {file, tool}, set ->
      if file in files do
        MapSet.put(set, tool)
      else
        set
      end
    end)
    |> Enum.to_list
  end

  defp contents(files) do
    {:ok, inner_files} = :erl_tar.extract({:binary, files["contents.tar.gz"]}, [:memory, :compressed])
    inner_files
    |> string_files
    |> MapSet.new(&elem(&1, 0))
  end

  defp string_files(files) do
    Enum.into(files, %{}, fn {name, binary} ->
      {List.to_string(name), binary}
    end)
  end

  defp list_files(files) do
    Enum.into(files, [], fn {name, binary} ->
      {String.to_char_list(name), binary}
    end)
  end
end

HexWeb.Scripts.Tarballs.main(System.argv)

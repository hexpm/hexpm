defmodule HexWeb.TestHelpers do
   @tmp Path.expand Path.join(__DIR__, "../../tmp")

  def create_tar(meta, files) do
    meta =
      meta
      |> Map.put_new(:app, meta[:name])
      |> Map.put_new(:build_tools, ["mix"])
      |> Map.put_new(:requirements, %{})

    contents_path = Path.join(@tmp, "#{meta[:name]}-#{meta[:version]}-contents.tar.gz")
    files = Enum.map(files, fn {name, bin} -> {String.to_char_list(name), bin} end)
    :ok = :erl_tar.create(contents_path, files, [:compressed])
    contents = File.read!(contents_path)

    meta_string = HexWeb.ConsultFormat.encode(meta)
    blob = "3" <> meta_string <> contents
    checksum = :crypto.hash(:sha256, blob) |> Base.encode16

    files = [
      {'VERSION', "3"},
      {'CHECKSUM', checksum},
      {'metadata.config', meta_string},
      {'contents.tar.gz', contents} ]
    path = Path.join(@tmp, "#{meta[:name]}-#{meta[:version]}.tar")
    :ok = :erl_tar.create(path, files)

    File.read!(path)
  end

  def rel_meta(params) do
    params = params(params)
    meta =
      params
      |> Map.put_new("build_tools", ["mix"])
      |> Map.put_new("requirements", %{})
    Map.put(params, "meta", meta)
  end

  def pkg_meta(meta) do
    params = params(meta)
    Map.update(params, "meta", params, &Map.merge(params, &1))
  end

  def params(params) do
    Enum.into(params, %{}, fn
      {binary, value} when is_binary(binary) -> {binary, value}
      {atom, value} when is_atom(atom) -> {Atom.to_string(atom), value}
    end)
  end
end

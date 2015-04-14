ExUnit.start exclude: [:integration]

File.rm_rf!("tmp")
File.mkdir_p!("tmp")

alias Ecto.Adapters.SQL

SQL.begin_test_transaction(HexWeb.Repo)

defmodule HexWebTest.Case do
  use ExUnit.CaseTemplate

  setup do
    SQL.restart_test_transaction(HexWeb.Repo)
  end

  using do
    quote do
      import HexWebTest.Case
    end
  end

  @tmp Path.expand Path.join(__DIR__, "../tmp")

  def create_tar(meta, files) do
    meta = Dict.put_new(meta, :app, meta[:name])

    contents_path = Path.join(@tmp, "#{meta[:name]}-#{meta[:version]}-contents.tar.gz")
    files = Enum.map(files, fn {name, bin} -> {String.to_char_list(name), bin} end)
    :ok = :erl_tar.create(contents_path, files, [:compressed])
    contents = File.read!(contents_path)

    meta_string = HexWeb.API.ConsultFormat.encode(meta)
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
end

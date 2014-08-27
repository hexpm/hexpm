ExUnit.start exclude: [:integration]

Mix.Task.run "ecto.drop", ["HexWeb.Repo"]
Mix.Task.run "ecto.create", ["HexWeb.Repo"]
Mix.Task.run "ecto.migrate", ["HexWeb.Repo"]

File.rm_rf!("tmp")
File.mkdir_p!("tmp")

defmodule HexWebTest.Case do
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.Postgres

  setup do
    Postgres.begin_test_transaction(HexWeb.Repo)
    on_exit fn ->
      Postgres.rollback_test_transaction(HexWeb.Repo)
    end
  end

  using do
    quote do
      import HexWebTest.Case
    end
  end

  @tmp Path.expand Path.join(__DIR__, "../tmp")

  def create_tar(version \\ 3, meta, files)

  def create_tar(2, meta, files) do
    contents_path = Path.join(@tmp, "#{meta[:app]}-#{meta[:version]}-contents.tar.gz")
    files = Enum.map(files, fn {name, bin} -> {String.to_char_list(name), bin} end)
    :ok = :erl_tar.create(contents_path, files, [:compressed])
    contents = File.read!(contents_path)

    meta_string = HexWeb.API.ElixirFormat.encode(meta)
    blob = "2" <> meta_string <> contents
    checksum = :crypto.hash(:sha256, blob) |> Base.encode16

    files = [
      {'VERSION', "2"},
      {'CHECKSUM', checksum},
      {'metadata.exs', meta_string},
      {'contents.tar.gz', contents} ]
    path = Path.join(@tmp, "#{meta[:app]}-#{meta[:version]}.tar")
    :ok = :erl_tar.create(path, files)

    File.read!(path)
  end

  def create_tar(3, meta, files) do
    contents_path = Path.join(@tmp, "#{meta[:app]}-#{meta[:version]}-contents.tar.gz")
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
    path = Path.join(@tmp, "#{meta[:app]}-#{meta[:version]}.tar")
    :ok = :erl_tar.create(path, files)

    File.read!(path)
  end
end

defmodule Hexpm.PreviewTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Preview

  test "source selects known files and rejects invalid paths" do
    put_release("source_package", "1.0.0", [
      {"mix.exs", "mix"},
      {"README.md", "readme"},
      {"lib/source.ex", "source"}
    ])

    assert {:ok, source} = Preview.source("source_package", "1.0.0", "lib/source.ex")
    assert source.filename == "lib/source.ex"
    assert source.contents == "source"
    assert source.type == :text

    assert Preview.source("source_package", "1.0.0", "../other/file") == :error
  end

  test "source reports binary and oversized files without returning their contents" do
    put_release("special_files", "1.0.0", [
      {"binary.bin", <<0xFF, 0xFE>>},
      {"large.txt", String.duplicate("x", 2_000_001)}
    ])

    assert {:ok, %{type: :binary, contents: nil}} =
             Preview.source("special_files", "1.0.0", "binary.bin")

    assert {:ok, %{type: {:too_large, 2_000_001}, contents: nil}} =
             Preview.source("special_files", "1.0.0", "large.txt")
  end

  test "source and readme return error for missing data" do
    assert Preview.source("missing", "1.0.0") == :error
    assert Preview.readme("missing", "1.0.0") == :error

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/incomplete-1.0.0.json",
      Jason.encode!(["README.md"])
    )

    assert Preview.source("incomplete", "1.0.0") == :error
    assert Preview.readme("incomplete", "1.0.0") == :error
  end

  test "readme uses the established filename priority" do
    put_release("readme_package", "1.0.0", [
      {"readme.txt", "lower"},
      {"README.md", "preferred"}
    ])

    assert Preview.readme("readme_package", "1.0.0") ==
             {:ok, "README.md", "preferred"}
  end

  test "source defaults to README, mix, rebar, Makefile, and the first file in order" do
    defaults = [
      {~w(lib.ex Makefile rebar.config mix.exs README.txt), "README.txt"},
      {~w(lib.ex Makefile rebar.config mix.exs), "mix.exs"},
      {~w(lib.ex Makefile rebar.config), "rebar.config"},
      {~w(lib.ex Makefile), "Makefile"},
      {~w(lib.ex other.ex), "lib.ex"}
    ]

    for {files, expected} <- defaults do
      package = "default_#{Path.rootname(expected)}"
      put_release(package, "1.0.0", Enum.map(files, &{&1, &1}))

      assert {:ok, %{filename: ^expected}} = Preview.source(package, "1.0.0")
    end
  end

  defp put_release(package, version, files) do
    filenames = Enum.map(files, &elem(&1, 0))

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/#{package}-#{version}.json",
      Jason.encode!(filenames)
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(:preview_bucket, "files/#{package}/#{version}/#{filename}", contents)
    end
  end
end

defmodule Hexpm.PreviewTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Preview

  test "source selects known files and rejects invalid paths" do
    put_release("hexpm", "source_package", "1.0.0", [
      {"mix.exs", "mix"},
      {"README.md", "readme"},
      {"lib/source.ex", "source"}
    ])

    assert {:ok, source} = Preview.source("hexpm", "source_package", "1.0.0", "lib/source.ex")
    assert source.filename == "lib/source.ex"
    assert source.contents == "source"
    assert source.type == :text

    assert Preview.source("hexpm", "source_package", "1.0.0", "../other/file") == :error
  end

  test "source reports binary and oversized files without returning their contents" do
    put_release("hexpm", "special_files", "1.0.0", [
      {"binary.bin", <<0xFF, 0xFE>>},
      {"large.txt", String.duplicate("x", 200_001)}
    ])

    assert {:ok, %{type: :binary, contents: nil}} =
             Preview.source("hexpm", "special_files", "1.0.0", "binary.bin")

    assert {:ok, %{type: {:too_large, 200_001}, contents: nil}} =
             Preview.source("hexpm", "special_files", "1.0.0", "large.txt")
  end

  test "source and readme return error for missing data" do
    assert Preview.source("hexpm", "missing", "1.0.0") == :error
    assert Preview.readme("hexpm", "missing", "1.0.0") == :error

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/incomplete-1.0.0.json",
      Jason.encode!(["README.md"])
    )

    assert Preview.source("hexpm", "incomplete", "1.0.0") == :error
    assert Preview.readme("hexpm", "incomplete", "1.0.0") == :error
  end

  test "readme uses the established filename priority" do
    put_release("hexpm", "readme_package", "1.0.0", [
      {"readme.txt", "lower"},
      {"README.md", "preferred"}
    ])

    assert Preview.readme("hexpm", "readme_package", "1.0.0") ==
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
      put_release("hexpm", package, "1.0.0", Enum.map(files, &{&1, &1}))

      assert {:ok, %{filename: ^expected}} = Preview.source("hexpm", package, "1.0.0")
    end
  end

  test "source, readme, and raw_file are scoped to the repository" do
    put_release("acme", "scoped", "1.0.0", [
      {"mix.exs", "private mix"},
      {"README.md", "private readme"}
    ])

    assert {:ok, source} = Preview.source("acme", "scoped", "1.0.0", "mix.exs")
    assert source.contents == "private mix"

    assert Preview.readme("acme", "scoped", "1.0.0") == {:ok, "README.md", "private readme"}
    assert Preview.raw_file("acme", "scoped", "1.0.0", "mix.exs") == {:ok, "private mix"}

    assert Preview.source("hexpm", "scoped", "1.0.0", "mix.exs") == :error
    assert Preview.readme("hexpm", "scoped", "1.0.0") == :error
    assert Preview.raw_file("hexpm", "scoped", "1.0.0", "mix.exs") == :error
  end

  test "raw_file only serves files from the file list" do
    put_release("hexpm", "raw_package", "1.0.0", [{"lib/raw.ex", "raw"}])

    Hexpm.Store.put(
      :preview_bucket,
      "files/raw_package/1.0.0/unlisted.ex",
      "unlisted"
    )

    assert Preview.raw_file("hexpm", "raw_package", "1.0.0", "lib/raw.ex") == {:ok, "raw"}
    assert Preview.raw_file("hexpm", "raw_package", "1.0.0", "unlisted.ex") == :error
    assert Preview.raw_file("hexpm", "raw_package", "1.0.0", "../secrets") == :error
  end

  test "surrogate keys are namespaced per repository" do
    assert Hexpm.Preview.Bucket.surrogate_keys("hexpm", "phoenix", "1.0.0") ==
             ["preview/package/phoenix", "preview/package/phoenix/version/1.0.0"]

    assert Hexpm.Preview.Bucket.surrogate_keys("acme", "phoenix", "1.0.0") ==
             ["preview/package/acme-phoenix", "preview/package/acme-phoenix/version/1.0.0"]
  end

  test "get_latest_version is scoped to the repository" do
    Hexpm.Store.put(:preview_bucket, "latest_versions/scoped", "1.0.0")
    Hexpm.Store.put(:preview_bucket, "repos/acme/latest_versions/scoped", "2.0.0")

    assert Preview.get_latest_version("hexpm", "scoped") == "1.0.0"
    assert Preview.get_latest_version("acme", "scoped") == "2.0.0"
    assert Preview.get_latest_version("other", "scoped") == nil
  end

  defp put_release(repository, package, version, files) do
    prefix = if repository == "hexpm", do: "", else: "repos/#{repository}/"
    filenames = Enum.map(files, &elem(&1, 0))

    Hexpm.Store.put(
      :preview_bucket,
      "#{prefix}file_lists/#{package}-#{version}.json",
      Jason.encode!(filenames)
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(
        :preview_bucket,
        "#{prefix}files/#{package}/#{version}/#{filename}",
        contents
      )
    end
  end
end

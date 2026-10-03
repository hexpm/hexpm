defmodule Hexpm.TarballLimitsTest do
  use ExUnit.Case, async: true

  import Hexpm.TarballHelpers, only: [tar_entry: 2, tar_entry: 3, tar_end: 0]

  alias Hexpm.TarballLimits

  @moduletag :tmp_dir

  describe "check_docs/1" do
    test "accepts 10,000 files", %{tmp_dir: tmp_dir} do
      path = write(tmp_dir, docs(files(10_000)))
      assert TarballLimits.check_docs(path) == :ok
    end

    test "rejects 10,001 files", %{tmp_dir: tmp_dir} do
      path = write(tmp_dir, docs(files(10_001)))
      assert TarballLimits.check_docs(path) == {:error, :too_many_entries}

      assert TarballLimits.format_error(:too_many_entries) ==
               "tarball has more than 10000 files"
    end

    test "counts directories as entries", %{tmp_dir: tmp_dir} do
      entries = for i <- 1..10_001, do: tar_entry("dir#{i}/", ?5)
      path = write(tmp_dir, :zlib.gzip([entries, tar_end()]))
      assert TarballLimits.check_docs(path) == {:error, :too_many_entries}
    end

    test "limits the path to 255 bytes", %{tmp_dir: tmp_dir} do
      ok = String.duplicate("a", 250) <> ".html"
      long = String.duplicate("a", 251) <> ".html"

      assert TarballLimits.check_docs(write(tmp_dir, docs([{ok, ""}]))) == :ok

      assert TarballLimits.check_docs(write(tmp_dir, docs([{long, ""}]))) ==
               {:error, {:path_too_long, long}}
    end

    test "limits the path to 16 levels", %{tmp_dir: tmp_dir} do
      ok = String.duplicate("d/", 15) <> "index.html"
      deep = String.duplicate("d/", 16) <> "index.html"

      assert TarballLimits.check_docs(write(tmp_dir, docs([{ok, ""}]))) == :ok

      assert TarballLimits.check_docs(write(tmp_dir, docs([{deep, ""}]))) ==
               {:error, {:path_too_deep, deep}}
    end

    test "reads GNU long names", %{tmp_dir: tmp_dir} do
      long = String.duplicate("a", 300)
      tar = [tar_entry("././@LongLink", ?L, long <> <<0>>), tar_entry("short", ?0), tar_end()]
      path = write(tmp_dir, :zlib.gzip(tar))

      assert TarballLimits.check_docs(path) == {:error, {:path_too_long, long}}
    end

    test "accepts regular files and directories", %{tmp_dir: tmp_dir} do
      tar = [tar_entry("dir/", ?5), tar_entry("dir/index.html", ?0, "html"), tar_end()]
      assert TarballLimits.check_docs(write(tmp_dir, :zlib.gzip(tar))) == :ok
    end

    test "rejects symlinks", %{tmp_dir: tmp_dir} do
      tar = [tar_entry("index.html", ?0, "html"), tar_entry("link", ?2), tar_end()]
      path = write(tmp_dir, :zlib.gzip(tar))

      assert TarballLimits.check_docs(path) == {:error, {:unsupported_type, "link", :symlink}}

      assert TarballLimits.format_error({:unsupported_type, "link", :symlink}) ==
               "unsupported file type in tarball: link (symlink)"
    end

    test "reads every gzip member", %{tmp_dir: tmp_dir} do
      first = :zlib.gzip(tar_entry("index.html", ?0, "html"))
      second = :zlib.gzip([Enum.map(files(10_000), &tar_entry(elem(&1, 0), ?0)), tar_end()])
      path = write(tmp_dir, first <> second)

      assert TarballLimits.check_docs(path) == {:error, :too_many_entries}
    end

    test "caps the sum of entry sizes", %{tmp_dir: tmp_dir} do
      entry = tar_entry("big", ?0, "")
      size = String.pad_leading(Integer.to_string(128 * 1024 * 1024 + 1, 8), 11, "0")
      <<before::binary-124, _::binary-11, rest::binary>> = entry
      entry = fix_checksum(before <> size <> rest)
      path = write(tmp_dir, :zlib.gzip([entry, tar_end()]))

      assert TarballLimits.check_docs(path) == {:error, :too_big}
    end

    test "rejects a bad header checksum", %{tmp_dir: tmp_dir} do
      <<before::binary-148, _::binary-8, rest::binary>> = tar_entry("index.html", ?0)
      path = write(tmp_dir, :zlib.gzip([before, "0000000\0", rest, tar_end()]))

      assert TarballLimits.check_docs(path) == {:error, {:invalid, :bad_header}}
    end

    test "rejects truncated gzip", %{tmp_dir: tmp_dir} do
      gzip = docs([{"index.html", :crypto.strong_rand_bytes(10_000)}])
      path = write(tmp_dir, binary_part(gzip, 0, byte_size(gzip) - 100))

      assert TarballLimits.check_docs(path) == {:error, {:invalid, :bad_gzip}}
    end
  end

  describe "check_package/1" do
    test "accepts symlinks", %{tmp_dir: tmp_dir} do
      tarball = create_tar(%{name: "foo", version: "1.0.0"}, [{"mix.exs", "mix.exs"}])
      %{tarball: tarball} = Hexpm.TarballHelpers.add_symlinks(tarball, [{"link", "mix.exs"}])

      assert TarballLimits.check_package(write(tmp_dir, tarball)) == :ok
    end

    test "rejects hard links and other special files", %{tmp_dir: tmp_dir} do
      for {typeflag, type} <- [{?1, :link}, {?3, :char}, {?6, :fifo}] do
        contents = :zlib.gzip([tar_entry("special", typeflag), tar_end()])
        path = write(tmp_dir, outer(contents))

        assert TarballLimits.check_package(path) ==
                 {:error, {:unsupported_type, "special", type}}
      end
    end

    test "rejects 10,001 files in the contents", %{tmp_dir: tmp_dir} do
      tarball = create_tar(%{name: "foo", version: "1.0.0"}, files(10_001))
      path = write(tmp_dir, tarball)

      assert TarballLimits.check_package(path) == {:error, :too_many_entries}
      assert TarballLimits.check_package_outer(path) == :ok
    end

    test "checks the last contents.tar.gz in the outer tarball", %{tmp_dir: tmp_dir} do
      good = :zlib.gzip([tar_entry("mix.exs", ?0), tar_end()])
      bad = :zlib.gzip([tar_entry("link", ?6), tar_end()])

      tar = [
        tar_entry("contents.tar.gz", ?0, good),
        tar_entry("contents.tar.gz", ?0, bad),
        tar_end()
      ]

      assert TarballLimits.check_package(write(tmp_dir, tar)) ==
               {:error, {:unsupported_type, "link", :fifo}}
    end

    test "allows only root regular files in the outer tarball", %{tmp_dir: tmp_dir} do
      contents = :zlib.gzip([tar_entry("mix.exs", ?0), tar_end()])

      path = write(tmp_dir, [tar_entry("dir/contents.tar.gz", ?0, contents), tar_end()])

      assert TarballLimits.check_package_outer(path) ==
               {:error, {:unexpected_file, "dir/contents.tar.gz"}}

      path = write(tmp_dir, [tar_entry("dir/", ?5), tar_end()])

      assert TarballLimits.check_package_outer(path) ==
               {:error, {:unsupported_type, "dir/", :directory}}
    end

    test "leaves tarballs over the compressed size limit to hex_tarball", %{tmp_dir: tmp_dir} do
      path = write(tmp_dir, :binary.copy(<<1>>, 16 * 1024 * 1024 + 1))
      assert TarballLimits.check_package(path) == :ok
    end
  end

  defp files(count), do: for(i <- 1..count, do: {"file#{i}.html", ""})

  defp docs(files) do
    {:ok, tarball} =
      :hex_tarball.create_docs(for {name, data} <- files, do: {to_charlist(name), data})

    tarball
  end

  defp outer(contents) do
    IO.iodata_to_binary([
      tar_entry("VERSION", ?0, "3"),
      tar_entry("contents.tar.gz", ?0, contents),
      tar_end()
    ])
  end

  defp create_tar(meta, files) do
    meta = Map.merge(%{app: meta.name, build_tools: ["mix"], requirements: %{}}, meta)
    files = for {name, data} <- files, do: {to_charlist(name), data}
    {:ok, %{tarball: tarball}} = :hex_tarball.create(meta, files)
    tarball
  end

  defp fix_checksum(header) do
    <<before::binary-148, _::binary-8, rest::binary>> = header
    blank = before <> "        " <> rest
    checksum = for <<byte <- binary_part(blank, 0, 512)>>, reduce: 0, do: (acc -> acc + byte)
    checksum = String.pad_leading(Integer.to_string(checksum, 8), 6, "0") <> "\0 "
    before <> checksum <> rest
  end

  defp write(tmp_dir, data) do
    path = Path.join(tmp_dir, "#{System.unique_integer([:positive])}.tar")
    File.write!(path, data)
    path
  end
end

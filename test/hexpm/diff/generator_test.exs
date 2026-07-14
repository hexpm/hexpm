defmodule Hexpm.Diff.FailingStore do
  @behaviour Hexpm.Store.Behaviour

  defdelegate list(bucket, prefix), to: Hexpm.Store.Memory
  defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
  defdelegate get_to_file(bucket, key, destination, opts), to: Hexpm.Store.Memory
  defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
  defdelegate delete(bucket, key), to: Hexpm.Store.Memory
  defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

  def put(bucket, key, body, opts) do
    if marker = Process.get(:fail_diff_key) do
      if String.contains?(key, marker),
        do: Process.get(:fail_diff_result),
        else: Hexpm.Store.Memory.put(bucket, key, body, opts)
    else
      Hexpm.Store.Memory.put(bucket, key, body, opts)
    end
  end
end

defmodule Hexpm.Diff.GeneratorTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  import Hexpm.DiffHelpers

  alias Hexpm.Diff.{Generator, Storage, Worker}

  test "generates stored diffs from verified tarballs with all supported file cases" do
    package = insert(:package, name: "generator_cases")

    insert_tarball_release(package, "1.0.0", %{
      "changed.ex" => "old = 1\n",
      "removed.txt" => "removed\n",
      "invalid.bin" => <<"old", 0xFF, "\n">>,
      "mode.sh" => {"echo same\n", 0o644},
      "huge.bin" => String.duplicate("a", 1024 * 1024 + 1)
    })

    insert_tarball_release(package, "2.0.0", %{
      "changed.ex" => "new = 2\n",
      "added.txt" => "added\n",
      "invalid.bin" => <<"new", 0xFE, "\n">>,
      "mode.sh" => {"echo same\n", 0o755},
      "huge.bin" => String.duplicate("b", 1024 * 1024 + 1)
    })

    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    assert :ok = Generator.generate(request)

    assert {:ok, metadata, pieces} = Hexpm.Diff.fetch(request)
    # metadata.config also changes because the package file list changed.
    assert metadata.files_changed == 7
    assert metadata.total_diffs == 7
    assert metadata.total_additions >= 3
    assert metadata.total_deletions >= 3

    loaded = Enum.map(pieces, &Hexpm.Diff.fetch_piece/1)
    assert Enum.any?(loaded, &match?({:ok, {:too_large, "huge.bin"}}, &1))

    raw_diffs = for {:ok, {:diff, diff, _, _}} <- loaded, do: diff
    assert Enum.any?(raw_diffs, &String.contains?(&1, "new file mode"))
    assert Enum.any?(raw_diffs, &String.contains?(&1, "deleted file mode"))
    assert Enum.any?(raw_diffs, &String.contains?(&1, "old mode"))
    assert Enum.any?(raw_diffs, &String.contains?(&1, "new mode"))
    assert Enum.all?(raw_diffs, &String.valid?/1)
    assert Enum.any?(raw_diffs, &String.contains?(&1, "?"))

    for {:ok, {:diff, diff, from_path, to_path}} <- loaded do
      assert {:ok, [_patch]} =
               GitDiff.parse_patch(diff, relative_from: from_path, relative_to: to_path)
    end

    assert :ok = Generator.generate(request)
    assert {:ok, ^metadata, repeated_pieces} = Hexpm.Diff.fetch(request)
    assert Enum.map(repeated_pieces, & &1.key) == Enum.map(pieces, & &1.key)
  end

  test "whitespace mode has a distinct cache and suppresses whitespace-only changes" do
    package = insert(:package, name: "generator_whitespace")
    insert_tarball_release(package, "1.0.0", %{"space.ex" => "value = 1\n"})
    insert_tarball_release(package, "2.0.0", %{"space.ex" => "value    =    1\n"})

    {:ok, normal} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    {:ok, ignored} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", ignore_whitespace: true)

    assert :ok = Generator.generate(normal)
    assert {:ok, %{total_diffs: 1}, [_]} = Hexpm.Diff.fetch(normal)

    assert :ok = Generator.generate(ignored)
    assert {:ok, %{total_diffs: 0, files_changed: 0}, []} = Hexpm.Diff.fetch(ignored)
  end

  test "checksum failures never write completion metadata" do
    package = insert(:package, name: "generator_checksum")
    insert_tarball_release(package, "1.0.0", %{"same" => "one"})
    insert_tarball_release(package, "2.0.0", %{"same" => "two"})

    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    request = %{request | from_checksum: <<0::256>>}

    assert {:error, :checksum_mismatch} = Generator.generate(request)
    assert :miss = Hexpm.Diff.fetch(request)
    refute cache_object(Storage.metadata_key(request, request.canonical_hash))
  end

  test "piece storage failure leaves no completion marker and retry overwrites partial pieces" do
    package = insert(:package, name: "generator_retry")
    insert_tarball_release(package, "1.0.0", %{"a.txt" => "old a", "b.txt" => "old b"})
    insert_tarball_release(package, "2.0.0", %{"a.txt" => "new a", "b.txt" => "new b"})
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    original_bucket = Application.fetch_env!(:hexpm, :diff_bucket)
    Application.put_env(:hexpm, :diff_bucket, {Hexpm.Diff.FailingStore, "diff_bucket"})

    on_exit(fn ->
      Application.put_env(:hexpm, :diff_bucket, original_bucket)
      Process.delete(:fail_diff_key)
      Process.delete(:fail_diff_result)
    end)

    Process.put(:fail_diff_key, "-diff-1.json")
    assert {:error, {%RuntimeError{}, _stacktrace}} = Generator.generate(request)
    assert cache_object(Storage.diff_key(request, request.canonical_hash, 0))
    refute cache_object(Storage.metadata_key(request, request.canonical_hash))

    Hexpm.Store.Memory.put(
      "diff_bucket",
      Storage.diff_key(request, request.canonical_hash, 0),
      "partial",
      []
    )

    Process.delete(:fail_diff_key)
    assert :ok = Generator.generate(request)
    refute cache_object(Storage.diff_key(request, request.canonical_hash, 0)) == "partial"
    assert {:ok, %{total_diffs: 2}, [_, _]} = Hexpm.Diff.fetch(request)
  end

  test "metadata storage failure leaves no completion marker" do
    package = insert(:package, name: "generator_metadata_failure")
    insert_tarball_release(package, "1.0.0", %{"a.txt" => "old"})
    insert_tarball_release(package, "2.0.0", %{"a.txt" => "new"})
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    original_bucket = Application.fetch_env!(:hexpm, :diff_bucket)
    Application.put_env(:hexpm, :diff_bucket, {Hexpm.Diff.FailingStore, "diff_bucket"})

    on_exit(fn ->
      Application.put_env(:hexpm, :diff_bucket, original_bucket)
      Process.delete(:fail_diff_key)
      Process.delete(:fail_diff_result)
    end)

    Process.put(:fail_diff_key, "metadata/")
    Process.put(:fail_diff_result, {:error, :unavailable})
    assert {:error, {%RuntimeError{}, _stacktrace}} = Generator.generate(request)
    assert :miss = Hexpm.Diff.fetch(request)
    assert cache_object(Storage.diff_key(request, request.canonical_hash, 0))
    refute cache_object(Storage.metadata_key(request, request.canonical_hash))
  end

  test "missing and invalid tarballs fail without writing metadata" do
    package = insert(:package, name: "generator_invalid_tarball")

    insert(:release,
      package: package,
      version: "1.0.0",
      outer_checksum: :crypto.hash(:sha256, "missing")
    )

    invalid = "not a tarball"

    insert(:release,
      package: package,
      version: "2.0.0",
      outer_checksum: :crypto.hash(:sha256, invalid)
    )

    Hexpm.Store.put(
      :repo_bucket,
      "tarballs/#{package.name}-2.0.0.tar",
      invalid,
      []
    )

    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    assert {:error, :tarball_not_found} = Generator.generate(request)
    assert :miss = Hexpm.Diff.fetch(request)

    Hexpm.Store.put(
      :repo_bucket,
      "tarballs/#{package.name}-1.0.0.tar",
      invalid,
      []
    )

    request = %{
      request
      | from_checksum: :crypto.hash(:sha256, invalid),
        canonical_hash:
          Hexpm.Diff.Request.cache_hash(
            request.cache_version,
            [:crypto.hash(:sha256, invalid), request.to_checksum],
            false
          )
    }

    assert {:error, {:invalid_tarball, _reason}} = Generator.generate(request)
    assert :miss = Hexpm.Diff.fetch(request)
  end

  test "queued jobs retain the cache version in their arguments across deploys" do
    package = insert(:package, name: "generator_cache_version")
    insert_tarball_release(package, "1.0.0", %{"a" => "old"})
    insert_tarball_release(package, "2.0.0", %{"a" => "new"})
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    args = Hexpm.Diff.Request.to_args(request)

    original_cache_version = Application.fetch_env!(:hexpm, :diff_cache_version)
    Application.put_env(:hexpm, :diff_cache_version, original_cache_version + 1)
    on_exit(fn -> Application.put_env(:hexpm, :diff_cache_version, original_cache_version) end)

    assert :ok = perform_job(Worker, args)
    assert {:ok, %{total_diffs: 1}, [_piece]} = Hexpm.Diff.fetch(request)
  end

  test "worker executes generation directly and rejects malformed arguments" do
    package = insert(:package, name: "generator_worker")
    insert_tarball_release(package, "1.0.0", %{"a" => "old"})
    insert_tarball_release(package, "2.0.0", %{"a" => "new"})
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    assert :ok = perform_job(Worker, Hexpm.Diff.Request.to_args(request))

    assert {:ok, %{total_diffs: 1, total_additions: 1, total_deletions: 1}, [_]} =
             Hexpm.Diff.fetch(request)

    assert {:error, :invalid_args} = perform_job(Worker, %{"package" => package.name})
  end
end

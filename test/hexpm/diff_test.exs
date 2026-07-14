defmodule Hexpm.DiffTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Diff.{Request, Storage, Worker}

  setup do
    package = insert(:package, name: "diff_context")
    from = insert(:release, package: package, version: "1.0.0", outer_checksum: <<1::256>>)
    to = insert(:release, package: package, version: "2.0.0", outer_checksum: <<2::256>>)
    {:ok, package: package, from: from, to: to}
  end

  test "prepares canonical and legacy standalone cache hashes", %{package: package} do
    assert {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    assert request.canonical_hash == :erlang.phash2({1, [<<1::256>>, <<2::256>>]})
    assert request.legacy_hash == :erlang.phash2({1, [<<2::256>>, <<1::256>>]})

    assert {:ok, whitespace} =
             Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", ignore_whitespace: true)

    assert whitespace.canonical_hash ==
             :erlang.phash2({{1, [<<1::256>>, <<2::256>>]}, [ignore_whitespace: true]})

    refute whitespace.canonical_hash == request.canonical_hash
  end

  test "reads canonical cache objects before reversed legacy objects", %{package: package} do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    legacy_metadata = %{total_diffs: 1, total_additions: 3, total_deletions: 2, files_changed: 1}
    legacy_piece = %{"type" => "too_large", "file" => "legacy.bin"}

    Hexpm.Store.put(
      :diff_bucket,
      Storage.metadata_key(request, request.legacy_hash),
      Jason.encode!(legacy_metadata),
      []
    )

    Hexpm.Store.put(
      :diff_bucket,
      Storage.diff_key(request, request.legacy_hash, 0),
      Jason.encode!(legacy_piece),
      []
    )

    assert {:ok, ^legacy_metadata, [piece]} = Hexpm.Diff.fetch(request)
    assert {:ok, {:too_large, "legacy.bin"}} = Hexpm.Diff.fetch_piece(piece)

    canonical_metadata =
      %{total_diffs: 0, total_additions: 0, total_deletions: 0, files_changed: 0}

    Hexpm.Store.put(
      :diff_bucket,
      Storage.metadata_key(request, request.canonical_hash),
      Jason.encode!(canonical_metadata),
      []
    )

    assert {:ok, ^canonical_metadata, []} = Hexpm.Diff.fetch(request)
  end

  test "keeps standalone object names and raw JSON format", %{package: package} do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    piece =
      Storage.put_piece!(request, 4, %{
        "diff" => "diff --git a/a b/a\n",
        "path_from" => "/tmp/from",
        "path_to" => "/tmp/to"
      })

    assert piece.key ==
             "diffs/#{package.name}-1.0.0-2.0.0-#{request.canonical_hash}-diff-4.json"

    assert {:ok, {:diff, "diff --git a/a b/a\n", "/tmp/from", "/tmp/to"}} =
             Hexpm.Diff.fetch_piece(piece)

    Storage.put_metadata!(request, %{
      total_diffs: 0,
      total_additions: 0,
      total_deletions: 0,
      files_changed: 0
    })

    assert Storage.metadata_key(request, request.canonical_hash) ==
             "metadata/#{package.name}-1.0.0-2.0.0-#{request.canonical_hash}.json"
  end

  test "validates public packages, releases, routes, and identical versions", %{package: package} do
    private_repository = insert(:repository)

    private_package =
      insert(:package, repository_id: private_repository.id, name: "private_diff")

    insert(:release, package: private_package, version: "1.0.0")

    assert {:error, :package_not_found} =
             Hexpm.Diff.prepare(private_package.name, "1.0.0", "2.0.0", [])

    assert {:error, :package_not_found} = Hexpm.Diff.prepare("missing", "1.0.0", "2.0.0", [])

    assert {:error, :release_not_found} =
             Hexpm.Diff.prepare(package.name, "0.1.0", "2.0.0", [])

    assert {:error, :invalid_version} = Hexpm.Diff.prepare(package.name, "bad", "2.0.0", [])

    assert {:error, :identical_versions} =
             Hexpm.Diff.prepare(package.name, "1.0.0", "1.0.0", [])
  end

  test "blank target resolves to latest stable with unstable fallback", %{package: package} do
    insert(:release, package: package, version: "2.1.0-rc.1")

    assert {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "", [])
    assert request.to == "2.0.0"

    unstable = insert(:package, name: "unstable_only")
    insert(:release, package: unstable, version: "0.1.0-rc.1")
    insert(:release, package: unstable, version: "0.2.0-rc.1")

    assert {:ok, request} = Hexpm.Diff.prepare(unstable.name, "0.1.0-rc.1", "", [])
    assert request.to == "0.2.0-rc.1"
  end

  test "rejects packages without releases" do
    package = insert(:package, name: "diff_without_releases")
    assert {:error, :no_releases} = Hexpm.Diff.prepare(package.name, "1.0.0", "", [])
  end

  test "enqueues one incomplete job and includes all cache identity arguments", %{
    package: package,
    to: to
  } do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    jobs =
      1..4
      |> Task.async_stream(fn _ -> Hexpm.Diff.enqueue(request) end, max_concurrency: 4)
      |> Enum.map(fn {:ok, {:ok, job}} -> job end)

    assert jobs |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 1
    assert Enum.any?(jobs, & &1.conflict?)

    assert_enqueued(
      worker: Worker,
      queue: :heavy,
      args: Request.to_args(request)
    )

    replacement_checksum = <<3::256>>
    to |> Ecto.Changeset.change(outer_checksum: replacement_checksum) |> Repo.update!()
    {:ok, replacement} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    assert {:ok, replacement_job} = Hexpm.Diff.enqueue(replacement)
    refute replacement_job.id == hd(jobs).id

    old_cache_version = Application.fetch_env!(:hexpm, :diff_cache_version)
    Application.put_env(:hexpm, :diff_cache_version, old_cache_version + 1)
    on_exit(fn -> Application.put_env(:hexpm, :diff_cache_version, old_cache_version) end)

    {:ok, recached} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    assert {:ok, recached_job} = Hexpm.Diff.enqueue(recached)
    refute recached_job.id in [hd(jobs).id, replacement_job.id]
  end

  test "reports domain job states without exposing Oban to callers", %{package: package} do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])
    {:ok, job} = Hexpm.Diff.enqueue(request)

    assert Hexpm.Diff.job_status(job) == :queued
    assert Hexpm.Diff.job_status(job.id) == :queued

    for {oban_state, diff_state} <- [
          {"executing", :running},
          {"retryable", :retrying},
          {"completed", :completed},
          {"discarded", :discarded},
          {"cancelled", :cancelled}
        ] do
      job = job |> Ecto.Changeset.change(state: oban_state) |> Repo.update!()
      assert Hexpm.Diff.job_status(job.id) == diff_state
    end

    Repo.delete!(job)
    assert Hexpm.Diff.job_status(job.id) == :missing
  end

  test "rejects malformed cache metadata and pieces", %{package: package} do
    {:ok, request} = Hexpm.Diff.prepare(package.name, "1.0.0", "2.0.0", [])

    Hexpm.Store.put(
      :diff_bucket,
      Storage.metadata_key(request, request.canonical_hash),
      Jason.encode!(%{total_diffs: -1}),
      []
    )

    assert {:error, :invalid_metadata} = Hexpm.Diff.fetch(request)

    Storage.put_metadata!(request, %{
      total_diffs: 1,
      total_additions: 0,
      total_deletions: 0,
      files_changed: 1
    })

    [piece] = elem(Hexpm.Diff.fetch(request), 2)
    Hexpm.Store.put(:diff_bucket, piece.key, Jason.encode!(%{unexpected: true}), [])
    assert {:error, :invalid_piece} = Hexpm.Diff.fetch_piece(piece)
  end
end

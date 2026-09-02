defmodule Hexpm.Hexdocs.WorkersTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Hexdocs.Workers

  defmodule ReplacingStore do
    @behaviour Hexpm.Store.Behaviour
    @replacement_key {__MODULE__, :replacement}

    defdelegate list(bucket, prefix), to: Hexpm.Store.Memory
    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate stream(bucket, key), to: Hexpm.Store.Memory
    defdelegate put(bucket, key, body, opts), to: Hexpm.Store.Memory
    defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
    defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

    # Serves the object once and then replaces it, so a job unpacks one
    # archive and finds another when it checks the store afterwards.
    def get_to_file(bucket, key, path, opts) do
      result = Hexpm.Store.Memory.get_to_file(bucket, key, path, opts)

      case :persistent_term.get(@replacement_key, nil) do
        {^key, body} ->
          :persistent_term.erase(@replacement_key)
          Hexpm.Store.Memory.put(bucket, key, body, [])

        _other ->
          :ok
      end

      result
    end

    def replace_after_read(key, body), do: :persistent_term.put(@replacement_key, {key, body})
    def clear, do: :persistent_term.erase(@replacement_key)
  end

  defmodule PublishingStore do
    @behaviour Hexpm.Store.Behaviour
    @hook_key {__MODULE__, :after_read}

    defdelegate list(bucket, prefix), to: Hexpm.Store.Memory
    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate stream(bucket, key), to: Hexpm.Store.Memory
    defdelegate put(bucket, key, body, opts), to: Hexpm.Store.Memory
    defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
    defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

    # Runs a hook once after the archive is read, standing in for another
    # release being published while the job is unpacking.
    def get_to_file(bucket, key, path, opts) do
      result = Hexpm.Store.Memory.get_to_file(bucket, key, path, opts)

      case :persistent_term.get(@hook_key, nil) do
        {^key, hook} ->
          :persistent_term.erase(@hook_key)
          hook.()

        _other ->
          :ok
      end

      result
    end

    def after_read(key, hook), do: :persistent_term.put(@hook_key, {key, hook})
    def clear, do: :persistent_term.erase(@hook_key)
  end

  defmodule FailingStore do
    @behaviour Hexpm.Store.Behaviour
    @failing_key {__MODULE__, :failing}

    defdelegate list(bucket, prefix), to: Hexpm.Store.Memory
    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate stream(bucket, key), to: Hexpm.Store.Memory
    defdelegate get_to_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
    defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

    def put(bucket, key, body, opts) do
      if key == :persistent_term.get(@failing_key, nil), do: raise("store down")
      Hexpm.Store.Memory.put(bucket, key, body, opts)
    end

    def fail_on(key), do: :persistent_term.put(@failing_key, key)
    def clear, do: :persistent_term.erase(@failing_key)
  end

  test "decides which version is the latest when it writes, not when it starts" do
    package = insert(:package, name: "racing_docs", docs_updated_at: DateTime.utc_now())
    insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-1.0.0.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, create_docs_tar([{"index.html", "1.0.0"}]))

    app_env(:hexpm, :repo_bucket, {PublishingStore, "repo_bucket"})
    on_exit(&PublishingStore.clear/0)

    PublishingStore.after_read(key, fn ->
      insert(:release, package: package, version: "2.0.0", has_docs: true)
    end)

    assert :ok = perform_job(Workers.Upload, %{key: key})

    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/index.html") =~ "1.0.0"
    refute Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html")
  end

  test "a docs revert during an upload leaves nothing behind" do
    package = insert(:package, name: "reverted_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-1.0.0.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, create_docs_tar([{"index.html", "1.0.0"}]))

    app_env(:hexpm, :repo_bucket, {PublishingStore, "repo_bucket"})
    on_exit(&PublishingStore.clear/0)

    PublishingStore.after_read(key, fn ->
      Ecto.Changeset.change(release, has_docs: false) |> Repo.update!()
      Hexpm.Store.delete(:repo_bucket, key)
    end)

    assert :ok = perform_job(Workers.Upload, %{key: key})

    refute Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/index.html")
    refute Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html")
    assert all_enqueued(worker: Hexpm.CDN.PurgeWorker) == []
  end

  test "the purges of finished writes survive a failure later in the upload" do
    package = insert(:package, name: "half_uploaded_docs", docs_updated_at: DateTime.utc_now())
    insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-1.0.0.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, create_docs_tar([{"index.html", "1.0.0"}]))

    app_env(:hexpm, :docs_bucket, {FailingStore, "docs_bucket"})
    on_exit(&FailingStore.clear/0)
    FailingStore.fail_on("#{package.name}/sitemap.xml")

    assert_raise RuntimeError, "store down", fn -> perform_job(Workers.Upload, %{key: key}) end

    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") =~ "1.0.0"

    assert_enqueued(
      worker: Hexpm.CDN.PurgeWorker,
      args: %{"keys" => ["docspage/#{package.name}/1.0.0"]}
    )

    assert_enqueued(
      worker: Hexpm.CDN.PurgeWorker,
      args: %{"keys" => ["docspage/#{package.name}"]}
    )
  end

  test "a sitemap job for an older version leaves the latest sitemap alone" do
    package = insert(:package, name: "sitemap_older_docs", docs_updated_at: DateTime.utc_now())
    insert(:release, package: package, version: "1.0.0", has_docs: true)
    insert(:release, package: package, version: "2.0.0", has_docs: true)
    key = "docs/#{package.name}-1.0.0.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, create_docs_tar([{"index.html", "1.0.0"}]))
    Hexpm.Store.put(:docs_bucket, "#{package.name}/sitemap.xml", "latest sitemap", [])

    assert :ok = perform_job(Workers.Sitemap, %{key: key})

    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/sitemap.xml") == "latest sitemap"
  end

  test "upload and delete are repeatable for public documentation" do
    package = insert(:package, name: "worker_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([{"index.html", "<html><head></head></html>"}])
    )

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") =~ "plausible"
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/index.html") =~ "plausible"

    Ecto.Changeset.change(release, has_docs: false) |> Repo.update!()
    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") == nil
  end

  test "a stale delete event restores docs that still exist" do
    package = insert(:package, name: "stale_delete_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([{"index.html", "<html><head></head></html>"}])
    )

    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") =~ "plausible"
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/index.html") =~ "plausible"
  end

  test "upload and delete verify the purged pages through their index.html" do
    package = insert(:package, name: "verified_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([{"index.html", "<html><head></head></html>"}, {"a.html", "a"}])
    )

    assert :ok = perform_job(Workers.Upload, %{key: key})

    index = Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/index.html")
    etag = ~s("#{Base.encode16(:crypto.hash(:md5, index), case: :lower)}")

    assert purge_args(["docspage/verified_docs/1.0.0"]) == %{
             "service" => "fastly_hexdocs",
             "keys" => ["docspage/verified_docs/1.0.0"],
             "verify" => [
               %{"url" => "http://verified-docs.localhost:5002/1.0.0/index.html", "etag" => etag}
             ]
           }

    assert purge_args(["docspage/verified_docs"]) == %{
             "service" => "fastly_hexdocs",
             "keys" => ["docspage/verified_docs"],
             "verify" => [
               %{"url" => "http://verified-docs.localhost:5002/index.html", "etag" => etag}
             ]
           }

    keys = ["docspage/verified_docs", "docspage/verified_docs/1.0.0"]

    Ecto.Changeset.change(release, has_docs: false) |> Repo.update!()
    assert :ok = perform_job(Workers.Delete, %{key: key})

    assert purge_args(keys) == %{
             "service" => "fastly_hexdocs",
             "keys" => keys,
             "verify" => [
               %{"url" => "http://verified-docs.localhost:5002/1.0.0/index.html", "etag" => nil},
               %{"url" => "http://verified-docs.localhost:5002/index.html", "etag" => nil}
             ]
           }
  end

  test "upload succeeds for archives with write-protected file modes" do
    package = insert(:package, name: "readonly_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([{"index.html", "<html><head></head></html>"}], 0o000)
    )

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") =~ "plausible"
  end

  test "search succeeds for archives without search data" do
    package = insert(:package, name: "search_docs")
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, create_docs_tar([{"index.html", "docs"}]))

    use_search_mock(fn ->
      expect(Hexpm.Hexdocs.Search.Mock, :delete, fn name, version ->
        assert name == package.name
        assert version == release.version
        :ok
      end)

      assert :ok = perform_job(Workers.Search, %{key: key})
    end)
  end

  test "search removes stale entries when replacement search data is empty" do
    package = insert(:package, name: "empty_search_docs")
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([{"search_data-#{package.name}.js", ~s(searchData={"items":[]})}])
    )

    use_search_mock(fn ->
      expect(Hexpm.Hexdocs.Search.Mock, :delete, fn name, version ->
        assert name == package.name
        assert version == release.version
        :ok
      end)

      assert :ok = perform_job(Workers.Search, %{key: key})
    end)
  end

  test "search preserves existing entries when replacement search data is malformed" do
    package = insert(:package, name: "malformed_search_docs")
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([{"search_data-#{package.name}.js", "searchData=not-json"}])
    )

    use_search_mock(fn ->
      assert_raise RuntimeError, ~r/Failed to decode search data json/, fn ->
        perform_job(Workers.Search, %{key: key})
      end
    end)
  end

  test "deleting latest docs promotes rewritten fallback docs" do
    package = insert(:package, name: "promoted_docs", docs_updated_at: DateTime.utc_now())
    fallback = insert(:release, package: package, version: "1.0.0", has_docs: true)
    removed = insert(:release, package: package, version: "2.0.0", has_docs: false)
    fallback_key = "docs/#{package.name}-#{fallback.version}.tar.gz"
    removed_key = "docs/#{package.name}-#{removed.version}.tar.gz"

    html =
      ~s(<html><head><link rel="canonical" href="https://hexdocs.pm/promoted_docs/"></head></html>)

    Hexpm.Store.put(:repo_bucket, fallback_key, create_docs_tar([{"index.html", html}]))
    Hexpm.Store.put(:docs_bucket, "#{package.name}/index.html", "removed latest")

    assert :ok = perform_job(Workers.Delete, %{key: removed_key})
    promoted = Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html")
    assert promoted =~ "plausible"
    refute promoted =~ "canonical"
  end

  test "deleting latest docs retries when the fallback archive is missing" do
    package = insert(:package, name: "missing_fallback", docs_updated_at: DateTime.utc_now())
    insert(:release, package: package, version: "1.0.0", has_docs: true)
    removed = insert(:release, package: package, version: "2.0.0", has_docs: false)
    removed_key = "docs/#{package.name}-#{removed.version}.tar.gz"

    assert_raise RuntimeError, ~r/Hexdocs archive not found in store/, fn ->
      perform_job(Workers.Delete, %{key: removed_key})
    end
  end

  test "sitemap lists indexable html pages at the package subdomain" do
    package = insert(:package, name: "sitemap_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([
        {"index.html", "docs"},
        {"asset.js", "js"},
        {"404.html", "missing"},
        {"search.html", "search"}
      ])
    )

    assert :ok = perform_job(Workers.Sitemap, %{key: key})
    sitemap = Hexpm.Store.get(:docs_bucket, "#{package.name}/sitemap.xml")
    assert sitemap =~ "http://sitemap-docs.localhost:5002/index.html"
    refute sitemap =~ "asset.js"
    refute sitemap =~ "404.html"
    refute sitemap =~ "search.html"

    etag = ~s("#{Base.encode16(:crypto.hash(:md5, sitemap), case: :lower)}")

    assert purge_args(["sitemap/#{package.name}"]) == %{
             "service" => "fastly_hexdocs",
             "keys" => ["sitemap/#{package.name}"],
             "verify" => [
               %{"url" => "http://sitemap-docs.localhost:5002/sitemap.xml", "etag" => etag}
             ]
           }
  end

  test "malformed archives fail so Oban can retry" do
    key = "docs/malformed-1.0.0.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, "not a tarball")

    assert_raise Hexpm.Hexdocs.Tar.UnpackError, fn ->
      perform_job(Workers.Search, %{key: key})
    end
  end

  test "upload snoozes when the archive changes while docs are uploading" do
    package = insert(:package, name: "replaced_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"
    index = "<html><head></head></html>"

    Hexpm.Store.put(
      :repo_bucket,
      key,
      create_docs_tar([{"index.html", index}, {"old.html", "old"}])
    )

    use_replacing_store(key, create_docs_tar([{"index.html", index}, {"new.html", "new"}]))

    assert {:snooze, 15} = perform_job(Workers.Upload, %{key: key, generation: "0001"})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/old.html") == nil
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/index.html") == nil

    assert :ok = perform_job(Workers.Upload, %{key: key, generation: "0002"})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/old.html") == nil
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/1.0.0/new.html") =~ "new"
  end

  test "search snoozes when the archive changes while indexing" do
    package = insert(:package, name: "replaced_search_docs")
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, create_docs_tar([{"index.html", "old"}]))
    use_replacing_store(key, create_docs_tar([{"index.html", "new"}]))

    use_search_mock(fn ->
      expect(Hexpm.Hexdocs.Search.Mock, :delete, fn _name, _version -> :ok end)

      assert {:snooze, 15} = perform_job(Workers.Search, %{key: key, generation: "0001"})
    end)
  end

  test "deleting latest docs snoozes when the fallback archive changes while promoting" do
    package =
      insert(:package, name: "replaced_fallback_docs", docs_updated_at: DateTime.utc_now())

    fallback = insert(:release, package: package, version: "1.0.0", has_docs: true)
    removed = insert(:release, package: package, version: "2.0.0", has_docs: false)
    fallback_key = "docs/#{package.name}-#{fallback.version}.tar.gz"
    removed_key = "docs/#{package.name}-#{removed.version}.tar.gz"
    Hexpm.Store.put(:repo_bucket, fallback_key, create_docs_tar([{"index.html", "old"}]))
    Hexpm.Store.put(:docs_bucket, "#{package.name}/index.html", "removed latest")
    use_replacing_store(fallback_key, create_docs_tar([{"index.html", "new"}]))

    assert {:snooze, 15} = perform_job(Workers.Delete, %{key: removed_key, generation: "0001"})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") =~ "old"

    assert :ok = perform_job(Workers.Delete, %{key: removed_key, generation: "0001"})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") =~ "new"
  end

  defp use_replacing_store(key, replacement) do
    original = Application.fetch_env!(:hexpm, :repo_bucket)
    Application.put_env(:hexpm, :repo_bucket, {ReplacingStore, "repo_bucket"})
    ReplacingStore.replace_after_read(key, replacement)

    on_exit(fn ->
      ReplacingStore.clear()
      Application.put_env(:hexpm, :repo_bucket, original)
    end)
  end

  defp use_search_mock(fun) do
    previous = Application.fetch_env!(:hexpm, :hexdocs_search_impl)
    Application.put_env(:hexpm, :hexdocs_search_impl, Hexpm.Hexdocs.Search.Mock)

    try do
      fun.()
    after
      Application.put_env(:hexpm, :hexdocs_search_impl, previous)
    end
  end
end

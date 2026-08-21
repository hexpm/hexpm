defmodule Hexpm.Hexdocs.WorkersTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Hexdocs.Workers

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

    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert Hexpm.Store.get(:docs_bucket, "#{package.name}/index.html") == nil
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

    assert_enqueued(
      worker: Hexpm.CDN.PurgeWorker,
      args: %{
        "service" => "fastly_hexdocs",
        "keys" => ["docspage/verified_docs", "docspage/verified_docs/1.0.0"],
        "verify" => [
          %{"url" => "http://verified-docs.localhost:5002/1.0.0/index.html", "etag" => etag},
          %{"url" => "http://verified-docs.localhost:5002/index.html", "etag" => etag}
        ]
      }
    )

    assert :ok = perform_job(Workers.Delete, %{key: key})

    assert_enqueued(
      worker: Hexpm.CDN.PurgeWorker,
      args: %{
        "service" => "fastly_hexdocs",
        "keys" => ["docspage/verified_docs", "docspage/verified_docs/1.0.0"],
        "verify" => [
          %{"url" => "http://verified-docs.localhost:5002/1.0.0/index.html", "etag" => nil},
          %{"url" => "http://verified-docs.localhost:5002/index.html", "etag" => nil}
        ]
      }
    )
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

    assert_enqueued(
      worker: Hexpm.CDN.PurgeWorker,
      args: %{
        "service" => "fastly_hexdocs",
        "keys" => ["sitemap/#{package.name}"],
        "verify" => [%{"url" => "http://sitemap-docs.localhost:5002/sitemap.xml", "etag" => etag}]
      }
    )
  end

  test "malformed archives fail so Oban can retry" do
    key = "docs/malformed-1.0.0.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, "not a tarball")

    assert_raise Hexpm.Hexdocs.Tar.UnpackError, fn ->
      perform_job(Workers.Search, %{key: key})
    end
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

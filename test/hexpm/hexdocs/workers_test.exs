defmodule Hexpm.Hexdocs.WorkersTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Hexdocs.{Tar, Workers}

  test "upload and delete are repeatable for public documentation" do
    package = insert(:package, name: "worker_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, Tar.create([{"index.html", "<html><head></head></html>"}]))

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert Hexpm.Store.get(:docs_public_bucket, "#{package.name}/index.html") =~ "plausible"
    assert Hexpm.Store.get(:docs_public_bucket, "#{package.name}/1.0.0/index.html") =~ "plausible"

    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert Hexpm.Store.get(:docs_public_bucket, "#{package.name}/index.html") == nil
  end

  test "search succeeds for archives without search data" do
    package = insert(:package, name: "search_docs")
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, Tar.create([{"index.html", "docs"}]))

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
      Tar.create([{"search_data-#{package.name}.js", ~s(searchData={"items":[]})}])
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
      Tar.create([{"search_data-#{package.name}.js", "searchData=not-json"}])
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

    html = ~s(<html><head><meta name="robots" content="noindex"></head></html>)
    Hexpm.Store.put(:repo_bucket, fallback_key, Tar.create([{"index.html", html}]))
    Hexpm.Store.put(:docs_public_bucket, "#{package.name}/index.html", "removed latest")

    assert :ok = perform_job(Workers.Delete, %{key: removed_key})
    promoted = Hexpm.Store.get(:docs_public_bucket, "#{package.name}/index.html")
    assert promoted =~ "plausible"
    refute promoted =~ ~s(content="noindex")
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

  test "sitemap extracts html pages from the archive" do
    package = insert(:package, name: "sitemap_docs", docs_updated_at: DateTime.utc_now())
    release = insert(:release, package: package, version: "1.0.0", has_docs: true)
    key = "docs/#{package.name}-#{release.version}.tar.gz"
    Hexpm.Store.put(:repo_bucket, key, Tar.create([{"index.html", "docs"}, {"asset.js", "js"}]))

    assert :ok = perform_job(Workers.Sitemap, %{key: key})
    sitemap = Hexpm.Store.get(:docs_public_bucket, "#{package.name}/sitemap.xml")
    assert sitemap =~ "#{package.name}/index.html"
    refute sitemap =~ "asset.js"
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

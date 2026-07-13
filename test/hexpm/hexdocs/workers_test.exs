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

    assert :ok = perform_job(Workers.Search, %{key: key})
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
end

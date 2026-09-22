defmodule Hexpm.OrphanedObjectsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.OrphanedObjects

  defp put(bucket, key), do: Hexpm.Store.put(bucket, key, "DATA", [])
  defp keys(bucket), do: bucket |> Hexpm.Store.list("") |> Enum.sort()

  defp sweep(bucket), do: OrphanedObjects.delete(buckets: [bucket], older_than: 0)[bucket]
  defp report(bucket), do: OrphanedObjects.scan(buckets: [bucket], older_than: 0)[bucket]

  defp live_package(opts \\ []) do
    repository_id = Keyword.get(opts, :repository_id, 1)
    package = insert(:package, repository_id: repository_id)
    insert(:release, package: package, version: "1.0.0")
    insert(:release, package: package, version: "2.0.0")
    package
  end

  defp documented_package(opts \\ []) do
    repository_id = Keyword.get(opts, :repository_id, 1)
    package = insert(:package, repository_id: repository_id)
    insert(:release, package: package, version: "1.0.0", has_docs: true)
    insert(:release, package: package, version: "2.0.0", has_docs: true)
    package
  end

  describe "scan/1" do
    test "reports orphans without deleting them" do
      package = live_package()
      put(:repo_bucket, "tarballs/#{package.name}-1.0.0.tar")
      put(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar")

      assert %{scanned: 2, orphaned: 1} = scanned = report(:repo_bucket)
      refute Map.has_key?(scanned, :deleted)

      assert keys(:repo_bucket) == [
               "tarballs/#{package.name}-1.0.0.tar",
               "tarballs/#{package.name}-9.9.9.tar"
             ]
    end

    test "rejects a bucket it does not sweep" do
      assert_raise ArgumentError, ~r/not a bucket this sweeps/, fn ->
        OrphanedObjects.scan(buckets: [:audit_bucket])
      end
    end

    test "rejects an older_than that is not a number of days" do
      assert_raise ArgumentError, ~r/:older_than takes a number of days/, fn ->
        OrphanedObjects.scan(older_than: "7")
      end
    end

    test "only looks under prefix" do
      package = live_package()
      put(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar")
      put(:repo_bucket, "docs/#{package.name}-9.9.9.tar.gz")

      assert %{scanned: 1, orphaned: 1} =
               OrphanedObjects.scan(buckets: [:repo_bucket], older_than: 0, prefix: "docs/")[
                 :repo_bucket
               ]
    end
  end

  describe "delete/1 on the repo bucket" do
    test "keeps the index, installs and debug objects" do
      put(:repo_bucket, "names")
      put(:repo_bucket, "versions")
      put(:repo_bucket, "installs/list.csv")
      put(:repo_bucket, "debug/tarballs/hexpm-foo-1.0.0-abc.tar.gz")

      assert %{deleted: 0, unrecognised: 0} = sweep(:repo_bucket)
      assert length(keys(:repo_bucket)) == 4
    end

    test "deletes the index of a repository that is gone" do
      repository = insert(:repository)
      put(:repo_bucket, "repos/#{repository.name}/names")
      put(:repo_bucket, "repos/gone/names")
      put(:repo_bucket, "repos/gone/versions")

      assert %{deleted: 2} = sweep(:repo_bucket)
      assert keys(:repo_bucket) == ["repos/#{repository.name}/names"]
    end

    test "records a repository that is gone for the backup, once" do
      repository = insert(:repository)
      put(:repo_bucket, "repos/#{repository.name}/names")
      put(:repo_bucket, "repos/gone/names")
      put(:repo_bucket, "repos/gone/tarballs/pkg-1.0.0.tar")
      put(:repo_bucket, "repos/gone-renamed/versions")

      assert %{deleted: 3} = sweep(:repo_bucket)

      assert keys(:deletions_bucket) == ["organizations/gone", "organizations/gone-renamed"]
      refute Hexpm.Store.get(:deletions_bucket, "organizations/#{repository.name}", [])
    end

    test "deletes tarballs, docs archives and registry objects of what is gone" do
      package = live_package()
      put(:repo_bucket, "packages/#{package.name}")
      put(:repo_bucket, "packages/gone_package")
      put(:repo_bucket, "tarballs/#{package.name}-1.0.0.tar")
      put(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar")
      put(:repo_bucket, "tarballs/gone_package-1.0.0.tar")
      put(:repo_bucket, "docs/#{package.name}-2.0.0.tar.gz")
      put(:repo_bucket, "docs/#{package.name}-9.9.9.tar.gz")

      assert %{deleted: 4} = sweep(:repo_bucket)

      assert keys(:repo_bucket) == [
               "docs/#{package.name}-2.0.0.tar.gz",
               "packages/#{package.name}",
               "tarballs/#{package.name}-1.0.0.tar"
             ]
    end

    test "deletes a policy object whose policy is gone" do
      repository = insert(:repository)

      Repo.insert!(%Hexpm.Repository.Policy{
        organization_id: repository.organization.id,
        name: "strict",
        visibility: "private",
        repositories: []
      })

      put(:repo_bucket, "repos/#{repository.name}/policies/strict")
      put(:repo_bucket, "repos/#{repository.name}/policies/gone")

      assert %{deleted: 1} = sweep(:repo_bucket)
      assert keys(:repo_bucket) == ["repos/#{repository.name}/policies/strict"]
    end

    test "keeps the docs archive of a package that has no rows to check" do
      put(:repo_bucket, "docs/elixir-1.18.0.tar.gz")
      put(:repo_bucket, "docs/mix-1.18.0.tar.gz")
      put(:repo_bucket, "docs/gone_package-1.0.0.tar.gz")

      assert %{deleted: 1, unrecognised: 0} = sweep(:repo_bucket)

      assert keys(:repo_bucket) == [
               "docs/elixir-1.18.0.tar.gz",
               "docs/mix-1.18.0.tar.gz"
             ]
    end

    test "reports a key it cannot place and never deletes it" do
      put(:repo_bucket, "something/we/have/not/seen")

      assert %{deleted: 0, unrecognised: 1, unrecognised_sample: ["something/we/have/not/seen"]} =
               sweep(:repo_bucket)

      assert keys(:repo_bucket) == ["something/we/have/not/seen"]
    end
  end

  describe "delete/1 on the preview bucket" do
    test "deletes files, file lists and latest versions of what is gone" do
      package = live_package()
      put(:preview_bucket, "files/#{package.name}/1.0.0/README.md")
      put(:preview_bucket, "files/#{package.name}/9.9.9/README.md")
      put(:preview_bucket, "file_lists/#{package.name}-1.0.0.json")
      put(:preview_bucket, "file_lists/#{package.name}-9.9.9.json")
      put(:preview_bucket, "latest_versions/#{package.name}")
      put(:preview_bucket, "latest_versions/gone_package")

      assert %{deleted: 3} = sweep(:preview_bucket)

      assert keys(:preview_bucket) == [
               "file_lists/#{package.name}-1.0.0.json",
               "files/#{package.name}/1.0.0/README.md",
               "latest_versions/#{package.name}"
             ]
    end

    test "reads the repository out of the repos prefix" do
      repository = insert(:repository)
      package = live_package(repository_id: repository.id)
      put(:preview_bucket, "repos/#{repository.name}/files/#{package.name}/1.0.0/README.md")
      put(:preview_bucket, "files/#{package.name}/1.0.0/README.md")

      assert %{deleted: 1} = sweep(:preview_bucket)

      assert keys(:preview_bucket) == [
               "repos/#{repository.name}/files/#{package.name}/1.0.0/README.md"
             ]
    end
  end

  describe "delete/1 on the docs buckets" do
    test "keeps the site-wide objects and the special packages" do
      put(:docs_bucket, "sitemap.xml")
      put(:docs_bucket, "package_names.csv")
      put(:docs_bucket, "org_names.csv")
      put(:docs_bucket, "elixir/main/index.html")
      put(:docs_bucket, "mix/1.18.0/index.html")

      assert %{deleted: 0, unrecognised: 0} = sweep(:docs_bucket)
      assert length(keys(:docs_bucket)) == 5
    end

    test "deletes pages of a version or a package that is gone" do
      package = documented_package()
      put(:docs_bucket, "#{package.name}/index.html")
      put(:docs_bucket, "#{package.name}/sitemap.xml")
      put(:docs_bucket, "#{package.name}/1.0.0/index.html")
      put(:docs_bucket, "#{package.name}/9.9.9/index.html")
      put(:docs_bucket, "gone_package/index.html")
      put(:docs_bucket, "gone_package/1.0.0/index.html")

      assert %{deleted: 3} = sweep(:docs_bucket)

      assert keys(:docs_bucket) == [
               "#{package.name}/1.0.0/index.html",
               "#{package.name}/index.html",
               "#{package.name}/sitemap.xml"
             ]
    end

    test "deletes the pages of a release that no longer carries docs" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0", has_docs: true)
      insert(:release, package: package, version: "2.0.0", has_docs: false)
      put(:docs_bucket, "#{package.name}/index.html")
      put(:docs_bucket, "#{package.name}/1.0.0/index.html")
      put(:docs_bucket, "#{package.name}/2.0.0/index.html")

      assert %{deleted: 1} = sweep(:docs_bucket)

      assert keys(:docs_bucket) == [
               "#{package.name}/1.0.0/index.html",
               "#{package.name}/index.html"
             ]
    end

    test "deletes the unversioned pages of a package with no documented release" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0", has_docs: false)
      put(:docs_bucket, "#{package.name}/index.html")
      put(:docs_bucket, "#{package.name}/sitemap.xml")

      assert %{deleted: 2} = sweep(:docs_bucket)
      assert keys(:docs_bucket) == []
    end

    test "takes the first segment of a private docs key as the repository" do
      repository = insert(:repository)
      package = documented_package(repository_id: repository.id)
      put(:docs_private_bucket, "#{repository.name}/#{package.name}/1.0.0/index.html")
      put(:docs_private_bucket, "#{repository.name}/#{package.name}/9.9.9/index.html")
      put(:docs_private_bucket, "gone_org/#{package.name}/1.0.0/index.html")

      assert %{deleted: 2} = sweep(:docs_private_bucket)

      assert keys(:docs_private_bucket) == [
               "#{repository.name}/#{package.name}/1.0.0/index.html"
             ]
    end
  end

  describe "delete/1 on the diff bucket" do
    test "keeps an entry whose two versions are both releases" do
      package = live_package()
      put(:diff_bucket, "metadata/#{package.name}-1.0.0-2.0.0-123.json")
      put(:diff_bucket, "diffs/#{package.name}-1.0.0-2.0.0-123-diff-0.json")

      assert %{deleted: 0, unrecognised: 0} = sweep(:diff_bucket)
      assert length(keys(:diff_bucket)) == 2
    end

    test "deletes an entry naming a version or package that is gone" do
      package = live_package()
      put(:diff_bucket, "metadata/#{package.name}-1.0.0-2.0.0-123.json")
      put(:diff_bucket, "metadata/#{package.name}-1.0.0-9.9.9-123.json")
      put(:diff_bucket, "diffs/#{package.name}-9.9.9-2.0.0-123-diff-0.json")
      put(:diff_bucket, "metadata/gone_package-1.0.0-2.0.0-123.json")

      assert %{deleted: 3} = sweep(:diff_bucket)
      assert keys(:diff_bucket) == ["metadata/#{package.name}-1.0.0-2.0.0-123.json"]
    end

    test "splits a pair where a version holds a hyphen of its own" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0-rc.1")
      insert(:release, package: package, version: "2.0.0")

      put(:diff_bucket, "metadata/#{package.name}-1.0.0-rc.1-2.0.0-123.json")
      put(:diff_bucket, "metadata/#{package.name}-1.0.0-rc.2-2.0.0-123.json")

      assert %{deleted: 1} = sweep(:diff_bucket)
      assert keys(:diff_bucket) == ["metadata/#{package.name}-1.0.0-rc.1-2.0.0-123.json"]
    end

    test "splits a pair where a prerelease contains the piece separator" do
      package = insert(:package)
      insert(:release, package: package, version: "1.0.0-diff-rc.1")
      insert(:release, package: package, version: "2.0.0")

      put(:diff_bucket, "diffs/#{package.name}-1.0.0-diff-rc.1-2.0.0-123-diff-0.json")
      put(:diff_bucket, "diffs/#{package.name}-1.0.0-diff-rc.2-2.0.0-123-diff-0.json")

      assert %{deleted: 1, unrecognised: 0} = sweep(:diff_bucket)

      assert keys(:diff_bucket) == [
               "diffs/#{package.name}-1.0.0-diff-rc.1-2.0.0-123-diff-0.json"
             ]
    end

    test "reports a key that is not shaped like a cache entry" do
      put(:diff_bucket, "metadata/no-hash-here.json")

      assert %{deleted: 0, unrecognised: 1} = sweep(:diff_bucket)
      assert keys(:diff_bucket) == ["metadata/no-hash-here.json"]
    end
  end

  describe "delete/1 age cutoff" do
    test "leaves an orphan written inside the window" do
      package = live_package()
      put(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar")

      assert %{orphaned: 0, too_recent: 1, deleted: 0} =
               OrphanedObjects.delete(buckets: [:repo_bucket], older_than: 7)[:repo_bucket]

      assert keys(:repo_bucket) == ["tarballs/#{package.name}-9.9.9.tar"]
    end

    test "deletes an orphan written before the window" do
      package = live_package()
      Hexpm.Store.Memory.written_at(DateTime.add(DateTime.utc_now(), -30, :day))
      put(:repo_bucket, "tarballs/#{package.name}-9.9.9.tar")

      assert %{orphaned: 1, too_recent: 0, deleted: 1} =
               OrphanedObjects.delete(buckets: [:repo_bucket], older_than: 7)[:repo_bucket]

      assert keys(:repo_bucket) == []
    end
  end

  describe "delete/1 limit" do
    test "stops collecting at the limit and says so" do
      package = live_package()

      for index <- 1..5 do
        put(:repo_bucket, "tarballs/#{package.name}-9.9.#{index}.tar")
      end

      assert %{orphaned: 2, truncated: true, deleted: 2} =
               OrphanedObjects.delete(buckets: [:repo_bucket], older_than: 0, limit: 2)[
                 :repo_bucket
               ]

      assert length(keys(:repo_bucket)) == 3
    end
  end
end

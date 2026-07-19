defmodule Hexpm.ReleaseTasks.MigratePreviewManifestsTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.Preview.Bucket
  alias Hexpm.ReleaseTasks.MigratePreviewManifests

  test "migrates manifests for public releases" do
    package = insert(:package, name: "manifest_task")
    insert(:release, package: package, version: "1.0.0")
    missing_package = insert(:package, name: "missing_manifest_task")
    insert(:release, package: missing_package, version: "1.0.0")
    repository = insert(:repository)

    private_package =
      insert(:package, name: "private_manifest_task", repository_id: repository.id)

    insert(:release, package: private_package, version: "1.0.0")

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/manifest_task-1.0.0.json",
      Jason.encode!(["README.md"])
    )

    Hexpm.Store.put(:preview_bucket, "files/manifest_task/1.0.0/README.md", "readme")

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/private_manifest_task-1.0.0.json",
      Jason.encode!(["README.md"])
    )

    Hexpm.Store.put(
      :preview_bucket,
      "files/private_manifest_task/1.0.0/README.md",
      "private"
    )

    assert MigratePreviewManifests.run(max_concurrency: 1) == %{migrated: 1, missing: 1}

    assert Bucket.get_manifest("manifest_task", "1.0.0") == %{
             files: ["README.md"],
             sizes: %{"README.md" => 6}
           }

    assert Bucket.get_manifest("private_manifest_task", "1.0.0") == nil

    assert MigratePreviewManifests.run(max_concurrency: 1) == %{current: 1, missing: 1}
  end
end

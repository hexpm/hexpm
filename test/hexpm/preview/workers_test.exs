defmodule Hexpm.Preview.WorkersTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Preview.Workers

  defmodule FailingStore do
    @behaviour Hexpm.Store.Behaviour

    defdelegate list(bucket, prefix), to: Hexpm.Store.Memory
    defdelegate list_with_sizes(bucket, prefix), to: Hexpm.Store.Memory
    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate get_to_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate put(bucket, key, body, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
    defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

    def put_file(_bucket, "files/manifest_preview/1.0.0/fail.txt", _path, _opts) do
      raise "simulated put failure"
    end

    def put_file(bucket, key, path, opts) do
      Hexpm.Store.Memory.put_file(bucket, key, path, opts)
    end
  end

  defmodule ActionStore do
    @behaviour Hexpm.Store.Behaviour
    @action_key {__MODULE__, :action}

    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate get_to_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate put(bucket, key, body, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
    defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory
    defdelegate list_with_sizes(bucket, prefix), to: Hexpm.Store.Memory

    def list(bucket, prefix) do
      run_action(:list, prefix)
      Hexpm.Store.Memory.list(bucket, prefix)
    end

    def put_file(bucket, key, path, opts) do
      result = Hexpm.Store.Memory.put_file(bucket, key, path, opts)
      run_action(:put_file, key)
      result
    end

    def set_action(operation, key, action) do
      :persistent_term.put(@action_key, {operation, key, action})
    end

    def clear_action, do: :persistent_term.erase(@action_key)

    defp run_action(operation, key) do
      case :persistent_term.get(@action_key, nil) do
        {^operation, ^key, action} ->
          :persistent_term.erase(@action_key)
          action.()

        _other ->
          :ok
      end
    end
  end

  defmodule FailingCDN do
    @behaviour Hexpm.CDN

    def purge_key(_service, _key), do: raise("simulated CDN failure")
    def public_ips, do: []
  end

  test "upload is repeatable and updates latest files" do
    package = insert(:package, name: "worker_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"

    put_tarball(key, package.name, to_string(release.version), [
      {"lib/foo.ex", "defmodule Foo do\nend"},
      {"hex_metadata.config", "metadata"}
    ])

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert :ok = perform_job(Workers.Upload, %{key: key})

    assert Hexpm.Preview.Bucket.get_manifest(package.name, "1.0.0") == %{
             files: ["lib/foo.ex"],
             sizes: %{"lib/foo.ex" => 20}
           }

    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/lib/foo.ex") =~
             "defmodule Foo"

    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == "1.0.0"
  end

  test "nonlatest uploads do not replace latest metadata" do
    package = insert(:package, name: "older_preview")
    old = insert(:release, package: package, version: "1.0.0")
    insert(:release, package: package, version: "2.0.0")
    key = "tarballs/#{package.name}-#{old.version}.tar"
    put_tarball(key, package.name, to_string(old.version), [{"README.md", "old"}])

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/README.md") == "old"
    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == nil
  end

  test "upload removes stale files" do
    package = insert(:package, name: "stale_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"
    put_tarball(key, package.name, to_string(release.version), [{"old.txt", "old"}])
    assert :ok = perform_job(Workers.Upload, %{key: key})

    put_tarball(key, package.name, to_string(release.version), [{"new.txt", "new"}])
    assert :ok = perform_job(Workers.Upload, %{key: key})

    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/old.txt") == nil
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/new.txt") == "new"
  end

  test "upload ignores private repository releases and removes stale public Preview files" do
    repository = insert(:repository)
    package = insert(:package, repository_id: repository.id, name: "private_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"
    file_key = "files/#{package.name}/#{release.version}/README.md"
    put_tarball(key, package.name, to_string(release.version), [{"README.md", "private"}])
    Hexpm.Store.put(:preview_bucket, file_key, "stale")

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert Hexpm.Store.get(:preview_bucket, file_key) == nil
    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == nil
  end

  test "upload normalizes safe archive paths" do
    package = insert(:package, name: "normalized_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"

    put_tarball(key, package.name, to_string(release.version), [
      {"lib/../safe.txt", "safe"},
      {"./dot.txt", "dot"}
    ])

    assert :ok = perform_job(Workers.Upload, %{key: key})

    assert Hexpm.Preview.Bucket.get_manifest(package.name, "1.0.0") == %{
             files: ["dot.txt", "safe.txt"],
             sizes: %{"dot.txt" => 3, "safe.txt" => 4}
           }
  end

  test "CDN failures retry cleanly" do
    package = insert(:package, name: "cdn_failure_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"
    put_tarball(key, package.name, to_string(release.version), [{"README.md", "readme"}])
    original_cdn = Application.fetch_env!(:hexpm, :cdn_impl)
    Application.put_env(:hexpm, :cdn_impl, FailingCDN)

    try do
      assert_raise RuntimeError, ~r/simulated CDN failure/, fn ->
        perform_job(Workers.Upload, %{key: key})
      end
    after
      Application.put_env(:hexpm, :cdn_impl, original_cdn)
    end

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/README.md") == "readme"
  end

  test "upload retries when the source tarball changes while files are uploading" do
    package = insert(:package, name: "replacement_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"
    put_tarball(key, package.name, to_string(release.version), [{"old.txt", "old"}])

    replacement =
      tarball(package.name, to_string(release.version), [{"new.txt", "new"}])

    use_action_store("files/#{package.name}/1.0.0/old.txt", fn ->
      Hexpm.Store.Memory.put("repo_bucket", key, replacement, [])
    end)

    assert_raise RuntimeError, ~r/Preview tarball changed while processing/, fn ->
      perform_job(Workers.Upload, %{key: key, generation: "0001"})
    end

    assert :ok = perform_job(Workers.Upload, %{key: key, generation: "0002"})
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/old.txt") == nil
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/new.txt") == "new"

    assert Hexpm.Preview.Bucket.get_manifest(package.name, "1.0.0") == %{
             files: ["new.txt"],
             sizes: %{"new.txt" => 3}
           }
  end

  test "upload publishes the file list after all files succeed" do
    package = insert(:package, name: "manifest_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"

    Hexpm.Store.put(
      :preview_bucket,
      "file_manifests/#{package.name}-1.0.0.json",
      preview_manifest([{"old.txt", "old"}])
    )

    put_tarball(key, package.name, to_string(release.version), [{"fail.txt", "failure"}])
    original_bucket = Application.fetch_env!(:hexpm, :preview_bucket)
    Application.put_env(:hexpm, :preview_bucket, {FailingStore, "preview_bucket"})
    on_exit(fn -> Application.put_env(:hexpm, :preview_bucket, original_bucket) end)

    trap_exit? = Process.flag(:trap_exit, true)

    try do
      assert_raise RuntimeError, ~r/simulated put failure/, fn ->
        perform_job(Workers.Upload, %{key: key})
      end
    after
      Process.flag(:trap_exit, trap_exit?)
    end

    assert Hexpm.Preview.Bucket.get_manifest(package.name, "1.0.0") == %{
             files: ["old.txt"],
             sizes: %{"old.txt" => 3}
           }
  end

  test "delete is repeatable" do
    package = insert(:package, name: "delete_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"
    put_tarball(key, package.name, to_string(release.version), [{"README.md", "readme"}])
    assert :ok = perform_job(Workers.Upload, %{key: key})
    Ecto.Changeset.change(release) |> Repo.delete!()

    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert Hexpm.Store.get(:preview_bucket, "file_manifests/#{package.name}-1.0.0.json") == nil
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/README.md") == nil
    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == nil
  end

  test "deleting the latest release promotes the current database latest release" do
    package = insert(:package, name: "promote_preview")
    old = insert(:release, package: package, version: "1.0.0")
    latest = insert(:release, package: package, version: "2.0.0")
    old_key = "tarballs/#{package.name}-#{old.version}.tar"
    latest_key = "tarballs/#{package.name}-#{latest.version}.tar"
    put_tarball(old_key, package.name, to_string(old.version), [{"old.txt", "old"}])
    put_tarball(latest_key, package.name, to_string(latest.version), [{"latest.txt", "latest"}])
    assert :ok = perform_job(Workers.Upload, %{key: old_key})
    assert :ok = perform_job(Workers.Upload, %{key: latest_key})
    Ecto.Changeset.change(latest) |> Repo.delete!()

    assert :ok = perform_job(Workers.Delete, %{key: latest_key})
    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == "1.0.0"
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/old.txt") == "old"
  end

  test "latest promotion skips a fallback deleted while it is uploading" do
    package = insert(:package, name: "promotion_race_preview")
    fallback = insert(:release, package: package, version: "1.0.0")
    latest = insert(:release, package: package, version: "2.0.0")
    fallback_key = "tarballs/#{package.name}-#{fallback.version}.tar"
    latest_key = "tarballs/#{package.name}-#{latest.version}.tar"
    put_tarball(fallback_key, package.name, to_string(fallback.version), [{"old.txt", "old"}])
    put_tarball(latest_key, package.name, to_string(latest.version), [{"latest.txt", "latest"}])
    assert :ok = perform_job(Workers.Upload, %{key: fallback_key})
    assert :ok = perform_job(Workers.Upload, %{key: latest_key})
    Ecto.Changeset.change(latest) |> Repo.delete!()

    use_action_store("files/#{package.name}/1.0.0/old.txt", fn ->
      Ecto.Changeset.change(fallback) |> Repo.delete!()
    end)

    assert :ok = perform_job(Workers.Delete, %{key: latest_key})
    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == nil
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/old.txt") == nil
  end

  test "a stale upload event does not restore a deleted release" do
    package = insert(:package, name: "stale_upload_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"
    put_tarball(key, package.name, to_string(release.version), [{"README.md", "readme"}])
    assert :ok = perform_job(Workers.Upload, %{key: key})
    Ecto.Changeset.change(release) |> Repo.delete!()

    assert :ok = perform_job(Workers.Upload, %{key: key})
    assert Hexpm.Store.get(:preview_bucket, "file_manifests/#{package.name}-1.0.0.json") == nil
    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == nil
  end

  test "a stale delete event restores a release that still exists" do
    package = insert(:package, name: "stale_delete_preview")
    release = insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-#{release.version}.tar"
    put_tarball(key, package.name, to_string(release.version), [{"README.md", "readme"}])

    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/README.md") == "readme"
    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == "1.0.0"
  end

  test "stale cleanup restores a nonlatest release republished while its prefix is listed" do
    package = insert(:package, name: "cleanup_race_preview")
    target = insert(:release, package: package, version: "1.0.0")
    latest = insert(:release, package: package, version: "2.0.0")
    target_key = "tarballs/#{package.name}-#{target.version}.tar"
    latest_key = "tarballs/#{package.name}-#{latest.version}.tar"
    put_tarball(target_key, package.name, to_string(target.version), [{"old.txt", "old"}])
    put_tarball(latest_key, package.name, to_string(latest.version), [{"latest.txt", "latest"}])
    assert :ok = perform_job(Workers.Upload, %{key: target_key})
    assert :ok = perform_job(Workers.Upload, %{key: latest_key})
    Ecto.Changeset.change(target) |> Repo.delete!()

    replacement = tarball(package.name, to_string(target.version), [{"new.txt", "new"}])

    use_action_store(:list, "files/#{package.name}/1.0.0/", fn ->
      insert(:release, package: package, version: "1.0.0")
      Hexpm.Store.Memory.put("repo_bucket", target_key, replacement, [])
      assert :ok = Hexpm.Preview.upload(target_key)
    end)

    assert :ok = perform_job(Workers.Delete, %{key: target_key, generation: "old-delete"})
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/old.txt") == nil
    assert Hexpm.Store.get(:preview_bucket, "files/#{package.name}/1.0.0/new.txt") == "new"

    assert Hexpm.Preview.Bucket.get_manifest(package.name, "1.0.0") == %{
             files: ["new.txt"],
             sizes: %{"new.txt" => 3}
           }

    assert Hexpm.Store.get(:preview_bucket, "latest_versions/#{package.name}") == "2.0.0"
  end

  test "delete removes partial files even when no file-list manifest exists" do
    package = "orphan_preview"
    version = "1.0.0"
    key = "tarballs/#{package}-#{version}.tar"
    Hexpm.Store.put(:preview_bucket, "files/#{package}/#{version}/partial.txt", "partial")

    assert :ok = perform_job(Workers.Delete, %{key: key})
    assert Hexpm.Store.get(:preview_bucket, "files/#{package}/#{version}/partial.txt") == nil
  end

  test "missing and malformed tarballs fail so Oban can retry" do
    package = insert(:package, name: "missing")
    insert(:release, package: package, version: "1.0.0")

    assert_raise RuntimeError, ~r/Preview tarball not found/, fn ->
      perform_job(Workers.Upload, %{key: "tarballs/missing-1.0.0.tar"})
    end

    package = insert(:package, name: "malformed")
    insert(:release, package: package, version: "1.0.0")
    Hexpm.Store.put(:repo_bucket, "tarballs/malformed-1.0.0.tar", "not a tarball")

    assert_raise RuntimeError, ~r/Failed to unpack Preview tarball/, fn ->
      perform_job(Workers.Upload, %{key: "tarballs/malformed-1.0.0.tar"})
    end
  end

  test "stale delete jobs retry when their tarballs are missing" do
    package = insert(:package, name: "missing_other_workers")
    insert(:release, package: package, version: "1.0.0")
    key = "tarballs/#{package.name}-1.0.0.tar"

    assert_raise RuntimeError, ~r/Preview tarball not found/, fn ->
      perform_job(Workers.Delete, %{key: key})
    end
  end

  defp put_tarball(key, package, version, files) do
    Hexpm.Store.put(:repo_bucket, key, tarball(package, version, files))
  end

  defp tarball(package, version, files) do
    metadata = %{"name" => package, "version" => version}
    files = Enum.map(files, fn {path, contents} -> {String.to_charlist(path), contents} end)
    {:ok, %{tarball: tarball}} = :hex_tarball.create(metadata, files)
    tarball
  end

  defp use_action_store(key, action), do: use_action_store(:put_file, key, action)

  defp use_action_store(operation, key, action) do
    original_bucket = Application.fetch_env!(:hexpm, :preview_bucket)
    Application.put_env(:hexpm, :preview_bucket, {ActionStore, "preview_bucket"})
    ActionStore.set_action(operation, key, action)

    on_exit(fn ->
      ActionStore.clear_action()
      Application.put_env(:hexpm, :preview_bucket, original_bucket)
    end)
  end
end

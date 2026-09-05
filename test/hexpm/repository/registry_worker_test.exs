defmodule Hexpm.Repository.RegistryWorkerTest do
  use Hexpm.DataCase, async: true
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.CDN.PurgeWorker
  alias Hexpm.Repository.{RegistryWorker, Repository}

  setup do
    package = insert(:package) |> Hexpm.Repo.preload(:repository)
    insert(:release, package: package, version: "0.0.1")
    %{package: package}
  end

  defp registry(path) do
    if contents = Hexpm.Store.get(:repo_bucket, path, []) do
      public_key = Application.fetch_env!(:hexpm, :public_key)
      {:ok, payload} = :hex_registry.decode_and_verify_signed(:zlib.gunzip(contents), public_key)
      payload
    end
  end

  defp etag(path) do
    body = Hexpm.Store.get(:repo_bucket, path, [])
    ~s("#{Base.encode16(:crypto.hash(:md5, body), case: :lower)}")
  end

  describe "package" do
    test "builds the package object and enqueues a verified purge", %{package: package} do
      {:ok, _} = RegistryWorker.enqueue_package(package)

      assert_enqueued(
        worker: RegistryWorker,
        queue: :registry,
        args: %{"type" => "package", "package_id" => package.id}
      )

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :registry)

      {:ok, decoded} =
        :hex_registry.decode_package(registry("packages/#{package.name}"), "hexpm", package.name)

      assert [%{version: "0.0.1"}] = decoded.releases

      keys = ["registry-package-#{package.name}", "registry-package/#{package.name}"]

      assert purge_args(keys) == %{
               "service" => "fastly_hexrepo",
               "keys" => keys,
               "verify" => [
                 %{
                   "url" => "http://localhost:5000/packages/#{package.name}",
                   "etag" => etag("packages/#{package.name}")
                 }
               ]
             }
    end

    test "verifies a private repository's object with its repository named" do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id) |> Hexpm.Repo.preload(:repository)
      insert(:release, package: package, version: "0.0.1")

      {:ok, _} = RegistryWorker.enqueue_package(package)
      assert %{success: 1} = Oban.drain_queue(queue: :registry)

      key = "repos/#{repository.name}/packages/#{package.name}"
      assert registry(key)

      keys = [
        "registry-package-#{package.name}",
        "registry-package/#{repository.name}/#{package.name}"
      ]

      assert purge_args(keys) == %{
               "service" => "fastly_hexrepo",
               "keys" => keys,
               "verify" => [
                 %{
                   "url" => "http://localhost:5000/#{key}",
                   "etag" => etag(key),
                   "repository" => repository.name
                 }
               ]
             }
    end

    test "discards the job when the package is gone", %{package: package} do
      {:ok, _} = RegistryWorker.enqueue_package(package)
      Hexpm.Repo.delete_all(assoc(package, :releases))
      Hexpm.Repo.delete!(package)

      assert %{discard: 1} = Oban.drain_queue(queue: :registry)
      refute_enqueued(worker: PurgeWorker)
    end

    test "takes over the queued package jobs of its repository and builds them together", %{
      package: package
    } do
      other = insert(:package) |> Hexpm.Repo.preload(:repository)
      insert(:release, package: other, version: "0.0.1")
      repository = insert(:repository)
      private = insert(:package, repository_id: repository.id) |> Hexpm.Repo.preload(:repository)
      insert(:release, package: private, version: "0.0.1")

      {:ok, _} = RegistryWorker.enqueue_package(package)
      {:ok, _} = RegistryWorker.enqueue_package(package)
      {:ok, _} = RegistryWorker.enqueue_package(other)
      {:ok, private_job} = RegistryWorker.enqueue_package(private)
      {:ok, _} = RegistryWorker.enqueue_package(package)

      assert %{success: 2, failure: 0} =
               Oban.drain_queue(queue: :registry, with_limit: 1, with_recursion: true)

      assert registry("packages/#{package.name}")
      assert registry("packages/#{other.name}")
      assert registry("repos/#{repository.name}/packages/#{private.name}")

      cancelled =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Hexpm.Repository.RegistryWorker" and j.state == "cancelled",
            select: j.args
          )
        )

      assert length(cancelled) == 3
      assert Repo.get!(Oban.Job, private_job.id).state == "completed"

      assert [%{args: %{"keys" => keys, "verify" => verify}}, %{args: %{"keys" => private_keys}}] =
               all_enqueued(worker: PurgeWorker) |> Enum.sort_by(& &1.id)

      assert Enum.sort(keys) ==
               Enum.sort([
                 "registry-package-#{package.name}",
                 "registry-package/#{package.name}",
                 "registry-package-#{other.name}",
                 "registry-package/#{other.name}"
               ])

      assert length(verify) == 2

      assert Enum.sort(private_keys) ==
               Enum.sort([
                 "registry-package-#{private.name}",
                 "registry-package/#{repository.name}/#{private.name}"
               ])
    end

    test "discards when none of the packages exist", %{package: package} do
      {:ok, job} = RegistryWorker.enqueue_package(package)
      Repo.delete_all(from(r in Hexpm.Repository.Release, where: r.package_id == ^package.id))
      Repo.delete!(package)

      assert %{discard: 1} = Oban.drain_queue(queue: :registry)
      assert Repo.get!(Oban.Job, job.id).state == "discarded"
    end
  end

  describe "repository (consolidation)" do
    test "cancels the queued jobs with the same arguments before building" do
      {:ok, _} = RegistryWorker.enqueue_repository(Repository.hexpm())
      {:ok, _} = RegistryWorker.enqueue_repository(Repository.hexpm())
      other = insert(:repository)
      {:ok, kept} = RegistryWorker.enqueue_repository(other)

      lines =
        capture_log_lines(fn ->
          assert %{success: 2, failure: 0} =
                   Oban.drain_queue(queue: :registry, with_limit: 1, with_recursion: true)
        end)

      assert [
               {:info,
                %{
                  message: "Registry built",
                  event: "registry.build",
                  job_type: "repository",
                  repository_id: hexpm_id,
                  consolidated: 1
                }},
               {:info, %{repository_id: other_id, consolidated: 0}}
             ] = Enum.filter(lines, fn {_level, fields} -> fields[:event] == "registry.build" end)

      assert hexpm_id == Repository.hexpm().id
      assert other_id == other.id

      states =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Hexpm.Repository.RegistryWorker",
            order_by: j.id,
            select: j.state
          )
        )

      assert states == ["completed", "cancelled", "completed"]
      assert Repo.get!(Oban.Job, kept.id).state == "completed"
      assert registry("names")
    end

    test "discards when the repository is gone" do
      repository = insert(:repository)
      {:ok, _} = RegistryWorker.enqueue_repository(repository)
      Repo.delete!(repository)

      assert %{discard: 1} = Oban.drain_queue(queue: :registry)
    end
  end

  describe "full" do
    test "cancels every queued job of the repository", %{package: package} do
      other_repository = insert(:repository)

      other =
        insert(:package, repository_id: other_repository.id) |> Hexpm.Repo.preload(:repository)

      insert(:release, package: other, version: "0.0.1")

      {:ok, _} = RegistryWorker.enqueue_full(Repository.hexpm())
      {:ok, _} = RegistryWorker.enqueue_package(package)
      {:ok, _} = RegistryWorker.enqueue_package_delete(package)
      {:ok, _} = RegistryWorker.enqueue_repository(Repository.hexpm())
      {:ok, _} = RegistryWorker.enqueue_full(Repository.hexpm())
      {:ok, kept} = RegistryWorker.enqueue_package(other)

      # priorities put the full build last, so run it first by hand
      [full | _] =
        Repo.all(
          from(j in Oban.Job,
            where: fragment("?->>'type' = 'full'", j.args),
            order_by: j.id
          )
        )

      assert :ok = RegistryWorker.perform(full)

      states =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Hexpm.Repository.RegistryWorker" and j.id != ^full.id,
            select: {j.args["type"], j.state}
          )
        )

      assert Enum.sort(states) ==
               Enum.sort([
                 {"package", "cancelled"},
                 {"package_delete", "cancelled"},
                 {"repository", "cancelled"},
                 {"full", "cancelled"},
                 {"package", "available"}
               ])

      assert Repo.get!(Oban.Job, kept.id).state == "available"
    end
  end

  describe "package_delete" do
    test "leaves the object alone when a package with the name exists again", %{
      package: package
    } do
      Hexpm.Store.put(:repo_bucket, "packages/#{package.name}", "DATA", [])

      {:ok, job} =
        %{
          "type" => "package_delete",
          "repository_id" => package.repository_id,
          "name" => package.name
        }
        |> RegistryWorker.new()
        |> Oban.insert()

      assert %{success: 1} = Oban.drain_queue(queue: :registry)
      assert Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", []) == "DATA"
      assert all_enqueued(worker: PurgeWorker) == []
      assert Repo.get!(Oban.Job, job.id).state == "completed"
    end

    test "removes the object and expects a 404", %{package: package} do
      Hexpm.Store.put(:repo_bucket, "packages/#{package.name}", "DATA", [])
      Repo.delete_all(from(r in Hexpm.Repository.Release, where: r.package_id == ^package.id))
      Repo.delete!(package)

      {:ok, _} = RegistryWorker.enqueue_package_delete(package)
      assert %{success: 1} = Oban.drain_queue(queue: :registry)

      refute Hexpm.Store.get(:repo_bucket, "packages/#{package.name}", [])

      keys = ["registry-package-#{package.name}", "registry-package/#{package.name}"]

      assert purge_args(keys) == %{
               "service" => "fastly_hexrepo",
               "keys" => keys,
               "verify" => [
                 %{"url" => "http://localhost:5000/packages/#{package.name}", "etag" => nil}
               ]
             }
    end
  end

  describe "repository" do
    test "builds names and versions and verifies both", %{package: package} do
      {:ok, _} = RegistryWorker.enqueue_repository(Repository.hexpm())
      assert %{success: 1} = Oban.drain_queue(queue: :registry)

      {:ok, names} = :hex_registry.decode_names(registry("names"), "hexpm")
      assert Enum.any?(names.packages, &(&1.name == package.name))

      assert purge_args(["registry-index"]) == %{
               "service" => "fastly_hexrepo",
               "keys" => ["registry-index"],
               "verify" => [
                 %{"url" => "http://localhost:5000/names", "etag" => etag("names")},
                 %{"url" => "http://localhost:5000/versions", "etag" => etag("versions")}
               ]
             }

      assert [%{args: %{"verify" => [%{"write" => write}, %{"write" => write}]}}] =
               all_enqueued(worker: PurgeWorker)
    end
  end

  describe "full (index)" do
    test "rebuilds everything and verifies the index objects", %{package: package} do
      {:ok, _} = RegistryWorker.enqueue_full(Repository.hexpm())
      assert %{success: 1} = Oban.drain_queue(queue: :registry)

      assert registry("packages/#{package.name}")

      assert purge_args(["registry"]) == %{
               "service" => "fastly_hexrepo",
               "keys" => ["registry"],
               "verify" => [
                 %{"url" => "http://localhost:5000/names", "etag" => etag("names")},
                 %{"url" => "http://localhost:5000/versions", "etag" => etag("versions")}
               ]
             }
    end
  end

  test "emits a build event with the type and result", %{package: package} do
    :telemetry.attach(
      "registry-build-#{inspect(self())}",
      [:hexpm, :registry_builder, :build, :stop],
      fn _event, measurements, metadata, pid -> send(pid, {:build, measurements, metadata}) end,
      self()
    )

    {:ok, _} = RegistryWorker.enqueue_package(package)
    Oban.drain_queue(queue: :registry)

    assert_receive {:build, %{duration: _}, %{type: :package, result: :ok}}
  end
end

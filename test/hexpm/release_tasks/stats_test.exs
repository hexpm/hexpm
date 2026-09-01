defmodule Hexpm.ReleaseTasks.StatsTest do
  use Hexpm.DataCase
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.CronMonitor.SentryMock
  alias Hexpm.Repository.Download
  alias Hexpm.Store
  alias Hexpm.ReleaseTasks.Stats

  setup :verify_on_exit!

  defmodule DroppingStore do
    @behaviour Hexpm.Store.Behaviour

    defdelegate list(bucket, prefix), to: Hexpm.Store.Memory
    defdelegate get(bucket, key, opts), to: Hexpm.Store.Memory
    defdelegate size(bucket, key), to: Hexpm.Store.Memory
    defdelegate get_to_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate put(bucket, key, body, opts), to: Hexpm.Store.Memory
    defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
    defdelegate delete(bucket, key), to: Hexpm.Store.Memory
    defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

    def stream(bucket, key) do
      Stream.concat(
        Hexpm.Store.Memory.stream(bucket, key),
        Stream.map([:eof], fn _ -> raise "connection dropped" end)
      )
    end
  end

  setup do
    repository1 = insert(:repository)
    [package1, package2, package3] = insert_list(3, :package)
    package4 = insert(:package, repository_id: repository1.id)
    insert(:release, package: package1, version: "0.0.1")
    insert(:release, package: package1, version: "0.0.2")
    insert(:release, package: package1, version: "0.1.0")
    insert(:release, package: package2, version: "0.0.1")
    insert(:release, package: package2, version: "0.0.2")
    insert(:release, package: package2, version: "0.0.3-rc.1")
    insert(:release, package: package3, version: "0.0.1")
    insert(:release, package: package4, version: "0.0.1")

    %{
      repository1: repository1,
      package1: package1,
      package2: package2,
      package3: package3,
      package4: package4
    }
  end

  test "parse_line/1" do
    assert Stats.parse_line(
             ~s{<134>2014-02-06T04:32:22Z cache-ams4138 S3Logging[216674]: 192.168.1.0 "Sat, 06 Feb 2014 04:32:22 GMT" "GET /tarballs/foo-0.0.1.tar" 200 "User-Agent"}
           ) == {"hexpm", "foo", "0.0.1"}

    assert Stats.parse_line(
             ~s{<134>2025-09-09T21:05:03Z cache-bma-essb1270021 logging_gcs[226941]: 98.128.175.50 [09/Sep/2025:21:05:03 +0000] "GET /tarballs/bar-0.1.0.tar" 200 "curl/8.7.1" 0}
           ) == {"hexpm", "bar", "0.1.0"}
  end

  test "counts all downloads", %{
    repository1: repository1,
    package1: package1,
    package2: package2,
    package4: package4
  } do
    logfile1 =
      read_log(
        "fastly_logs_1.txt",
        repository1: repository1.name,
        package1: package1.name,
        package2: package2.name,
        package4: package4.name
      )
      |> :zlib.gzip()

    logfile2 =
      read_log(
        "fastly_logs_2.txt",
        repository1: repository1.name,
        package1: package1.name,
        package2: package2.name,
        package4: package4.name
      )
      |> :zlib.gzip()

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2013-11-01/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile1,
      []
    )

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2013-11-01/2013-11-01T15:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile2,
      []
    )

    expect_monitor(:ok)
    assert :ok = perform_job(Stats, %{"date" => "2013-11-01"})
    assert :ok = Stats.run(~D[2013-11-01])

    rel1 = Repo.get_by!(assoc(package1, :releases), version: "0.0.1")
    rel2 = Repo.get_by!(assoc(package1, :releases), version: "0.0.2")
    rel3 = Repo.get_by!(assoc(package2, :releases), version: "0.0.2")
    rel4 = Repo.get_by!(assoc(package2, :releases), version: "0.0.3-rc.1")
    rel5 = Repo.get_by!(assoc(package4, :releases), version: "0.0.1")

    downloads = Hexpm.Repo.all(Download)
    assert length(downloads) == 4

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 6
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 1
    assert Enum.find(downloads, &(&1.release_id == rel5.id)).downloads == 1
    refute Enum.find(downloads, &(&1.release_id == rel4.id))
  end

  test "counts a multi-member gzip object in full", %{
    repository1: repository1,
    package1: package1,
    package2: package2,
    package4: package4
  } do
    replaces = [
      repository1: repository1.name,
      package1: package1.name,
      package2: package2.name,
      package4: package4.name
    ]

    logfile =
      :zlib.gzip(read_log("fastly_logs_1.txt", replaces)) <>
        :zlib.gzip(read_log("fastly_logs_2.txt", replaces))

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2013-11-01/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile,
      []
    )

    expect_monitor(:ok)
    assert :ok = perform_job(Stats, %{"date" => "2013-11-01"})

    rel1 = Repo.get_by!(assoc(package1, :releases), version: "0.0.1")
    rel2 = Repo.get_by!(assoc(package1, :releases), version: "0.0.2")
    rel3 = Repo.get_by!(assoc(package2, :releases), version: "0.0.2")
    rel5 = Repo.get_by!(assoc(package4, :releases), version: "0.0.1")

    downloads = Hexpm.Repo.all(Download)
    assert length(downloads) == 4

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 6
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 1
    assert Enum.find(downloads, &(&1.release_id == rel5.id)).downloads == 1
  end

  test "counts lines that straddle stream chunks", %{package1: package1} do
    versions = ~w(0.0.1 0.0.2 0.1.0)

    lines =
      for i <- 1..30_000 do
        version = Enum.at(versions, rem(i, 3))
        agent = Base.encode16(:crypto.strong_rand_bytes(16))

        ~s{<134>2025-09-09T21:05:03Z cache-bma-essb1270021 logging_gcs[226941]: 98.128.175.50 [09/Sep/2025:21:05:03 +0000] "GET /tarballs/#{package1.name}-#{version}.tar" 200 "#{agent}" 0}
      end

    logfile = :zlib.gzip(Enum.join(lines, "\n") <> "\n")
    assert byte_size(logfile) > 4 * 65_536

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2025-09-09/2025-09-09T21:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile,
      []
    )

    expect_monitor(:ok)
    assert :ok = perform_job(Stats, %{"date" => "2025-09-09"})

    downloads = Hexpm.Repo.all(Download)
    assert length(downloads) == 3

    for version <- versions do
      release = Repo.get_by!(assoc(package1, :releases), version: version)
      assert Enum.find(downloads, &(&1.release_id == release.id)).downloads == 10_000
    end
  end

  test "scheduled jobs process the previous UTC date", %{
    repository1: repository1,
    package1: package1,
    package2: package2,
    package4: package4
  } do
    release = Repo.get_by!(assoc(package1, :releases), version: "0.0.1")

    target =
      insert(:download,
        package: package1,
        release: release,
        day: ~D[2013-11-01],
        downloads: 10
      )

    other =
      insert(:download,
        package: package1,
        release: release,
        day: ~D[2013-11-02],
        downloads: 20
      )

    logfile =
      read_log(
        "fastly_logs_2.txt",
        repository1: repository1.name,
        package1: package1.name,
        package2: package2.name,
        package4: package4.name
      )
      |> :zlib.gzip()

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2013-11-01/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile,
      []
    )

    expect_monitor(:ok)

    assert :ok =
             perform_job(Stats, %{},
               scheduled_at: DateTime.new!(~D[2013-11-02], ~T[01:00:00], "Etc/UTC")
             )

    refute Repo.get(Download, target.id)
    assert Repo.get_by!(Download, release_id: release.id, day: ~D[2013-11-01]).downloads == 3
    assert Repo.get(Download, other.id)
  end

  @tag :capture_log
  test "a day without downloads fails instead of replacing the rows with nothing", %{
    package1: package1
  } do
    release = Repo.get_by!(assoc(package1, :releases), version: "0.0.1")

    existing =
      insert(:download,
        package: package1,
        release: release,
        day: ~D[2013-11-01],
        downloads: 10
      )

    Store.put(
      :logs_bucket,
      "fastly_hex/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      :zlib.gzip("not under the day prefix"),
      []
    )

    expect_monitor(:error)

    assert_raise RuntimeError, ~r/no downloads found for 2013-11-01/, fn ->
      perform_job(Stats, %{"date" => "2013-11-01"})
    end

    assert Repo.get(Download, existing.id)
    assert :ok = Stats.run(~D[2013-11-01], true)
  end

  test "a day without downloads completes when downloads are not expected" do
    Application.put_env(:hexpm, :stats_expect_downloads, false)
    on_exit(fn -> Application.put_env(:hexpm, :stats_expect_downloads, true) end)

    expect_monitor(:ok)

    assert :ok = perform_job(Stats, %{"date" => "2013-11-01"})
  end

  test "invalid dates cancel without retrying" do
    assert {:cancel, {:invalid_date, "not-a-date"}} =
             perform_job(Stats, %{"date" => "not-a-date"})
  end

  @tag :capture_log
  test "processing failures propagate for Oban retries and report an error check-in" do
    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2013-11-01/2013-11-01T14:00:00.000-invalid.log.gz",
      "not gzip data",
      []
    )

    expect_monitor(:error)

    assert_raise Oban.CrashError, fn ->
      perform_job(Stats, %{},
        scheduled_at: DateTime.new!(~D[2013-11-02], ~T[01:00:00], "Etc/UTC")
      )
    end
  end

  @tag :capture_log
  test "a failure while reading an object is reported as itself", %{package1: package1} do
    app_env(:hexpm, :logs_bucket, {DroppingStore, "logs_bucket"})

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2013-11-01/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      :zlib.gzip(read_log("fastly_logs_2.txt", package1: package1.name)),
      []
    )

    expect_monitor(:error)

    error =
      assert_raise RuntimeError, fn ->
        perform_job(Stats, %{"date" => "2013-11-01"})
      end

    assert Exception.message(error) =~ "connection dropped"
    refute Exception.message(error) =~ "data_error"
  end

  test "counts an object that expands a thousandfold", %{package1: package1} do
    line =
      ~s{<134>2025-09-09T21:05:03Z cache-bma-essb1270021 logging_gcs[226941]: 98.128.175.50 [09/Sep/2025:21:05:03 +0000] "GET /tarballs/#{package1.name}-0.0.1.tar" 200 "Hex/2.1.1" 0\n}

    logfile = :zlib.gzip(String.duplicate(line, 300_000))
    assert byte_size(logfile) * 100 < byte_size(line) * 300_000

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2025-09-09/2025-09-09T21:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile,
      []
    )

    expect_monitor(:ok)
    assert :ok = perform_job(Stats, %{"date" => "2025-09-09"})

    release = Repo.get_by!(assoc(package1, :releases), version: "0.0.1")

    assert Repo.get_by!(Download, release_id: release.id, day: ~D[2025-09-09]).downloads ==
             300_000
  end

  test "counts every batch of a large object, including a partial last one", %{
    package1: package1,
    package2: package2
  } do
    lines =
      for i <- 1..12_345 do
        {package, version} =
          case rem(i, 4) do
            0 -> {package1.name, "0.0.1"}
            1 -> {package1.name, "0.0.2"}
            2 -> {package2.name, "0.0.1"}
            3 -> {package2.name, "0.0.3-rc.1"}
          end

        ~s{<134>2025-09-09T21:05:03Z cache-bma-essb1270021 logging_gcs[226941]: 98.128.175.50 [09/Sep/2025:21:05:03 +0000] "GET /tarballs/#{package}-#{version}.tar" 200 "Hex/2.1.1" 0}
      end

    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2025-09-09/daily.log.gz",
      :zlib.gzip(Enum.join(lines, "\n") <> "\n"),
      []
    )

    expect_monitor(:ok)
    assert :ok = perform_job(Stats, %{"date" => "2025-09-09"})

    counts =
      for {package, version, expected} <- [
            {package1, "0.0.1", 3_086},
            {package1, "0.0.2", 3_087},
            {package2, "0.0.1", 3_086},
            {package2, "0.0.3-rc.1", 3_086}
          ] do
        release = Repo.get_by!(assoc(package, :releases), version: version)
        {Repo.get_by!(Download, release_id: release.id, day: ~D[2025-09-09]).downloads, expected}
      end

    assert Enum.all?(counts, fn {got, expected} -> got == expected end), inspect(counts)
    assert Enum.sum(Enum.map(counts, &elem(&1, 0))) == 12_345
  end

  @tag :capture_log
  test "a log line longer than the limit fails the job" do
    Store.put(
      :logs_bucket,
      "fastly_hex/dt=2013-11-01/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      :zlib.gzip(String.duplicate("x", 2 * 1024 * 1024)),
      []
    )

    expect_monitor(:error)

    error =
      assert_raise RuntimeError, fn ->
        perform_job(Stats, %{"date" => "2013-11-01"})
      end

    assert Exception.message(error) =~ "longer than 1048576 bytes"
  end

  defp expect_monitor(final_status) do
    app_env(:hexpm, :sentry_impl, SentryMock)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts[:status] == :in_progress
      assert opts[:monitor_slug] == "hexpm-stats"

      assert opts[:monitor_config] == [
               schedule: [type: :crontab, value: "0 1 * * *"],
               timezone: "Etc/UTC"
             ]

      {:ok, "check-in-id"}
    end)

    expect(SentryMock, :capture_check_in, fn opts ->
      assert opts == [
               check_in_id: "check-in-id",
               status: final_status,
               monitor_slug: "hexpm-stats"
             ]

      :ignored
    end)
  end

  describe "vacuum_downloads/0" do
    # The sandboxed tests above run with skip_maintenance_vacuum on, because
    # VACUUM cannot run inside the transaction wrapping them. This one goes
    # unboxed on a real connection so the statement is genuinely issued.
    test "runs against a real connection" do
      app_env(:hexpm, :skip_maintenance_vacuum, false)

      task = Hexpm.ConcurrencyCase.unboxed_task(fn -> Stats.vacuum_downloads() end)

      assert Task.await(task, 15_000) == :ok
    end

    test "issues no statement when disabled" do
      app_env(:hexpm, :skip_maintenance_vacuum, true)

      queries = capture_queries(fn -> assert Stats.vacuum_downloads() == :ok end)

      refute Enum.any?(queries, &(&1 =~ "VACUUM"))
    end
  end

  defp read_log(path, replaces) do
    Enum.reduce(replaces, read_fixture(path), fn {key, value}, file ->
      String.replace(file, "{#{key}}", value)
    end)
  end
end

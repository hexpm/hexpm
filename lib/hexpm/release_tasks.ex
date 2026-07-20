defmodule Hexpm.ReleaseTasks do
  alias Hexpm.ReleaseTasks.{CheckNames, PurgeExpiredRecords, Stats}
  require Logger

  @start_apps [
    :logger,
    :sentry
  ]

  @repo_apps [
    :crypto,
    :ssl,
    :postgrex,
    :ecto_sql
  ]

  @repos Application.compile_env!(:hexpm, :ecto_repos)

  def script(args) do
    start_apps(@start_apps)
    Logger.info("[task] Running script")
    start_app()

    task(fn -> run_script(args) end)

    Logger.info("[task] Finished script")
    stop()
  end

  def check_names() do
    start_apps(@start_apps)
    Logger.info("[task] Running check_names")
    start_app()

    monitor("hexpm-check-names", "30 0 * * *", fn ->
      run_scheduled("check_names", &CheckNames.run/0)
    end)

    Logger.info("[task] Finished check_names")
    stop()
  end

  def migrate(args \\ []) do
    start_apps(@start_apps)
    Logger.info("[task] Running migrate")
    start_repo()

    task(fn -> run_migrations(args) end)

    Logger.info("[task] Finished migrate")
    stop()
  end

  def rollback(args \\ []) do
    start_apps(@start_apps)
    Logger.info("[task] Running rollback")
    start_repo()

    task(fn -> run_rollback(args) end)

    Logger.info("[task] Finished rollback")
    stop()
  end

  def seed(args \\ []) do
    start_apps(@start_apps)
    Logger.info("[task] Running seed")

    task(fn ->
      start_repo()
      run_migrations(args)
      run_seeds()
    end)

    Logger.info("[task] Finished seed")
    stop()
  end

  def stats() do
    start_apps(@start_apps)
    Logger.info("[task] Running stats")
    start_app()

    monitor("hexpm-stats", "0 1 * * *", fn -> run_scheduled("stats", &Stats.run/0) end)

    Logger.info("[task] Finished stats")
    stop()
  end

  def purge_expired_records() do
    start_apps(@start_apps)
    Logger.info("[task] Running purge_expired_records")
    start_repo()

    monitor("hexpm-purge-expired-records", "0 2 * * *", fn ->
      run_scheduled("purge_expired_records", &PurgeExpiredRecords.run/0)
    end)

    Logger.info("[task] Finished purge_expired_records")
    stop()
  end

  # Wraps a task in a Sentry cron check-in so failures and missed runs surface
  # in Sentry. `slug` identifies the monitor and `schedule` is its crontab (UTC),
  # matching the Kubernetes CronJob that invokes the task.
  @doc false
  def monitor(slug, schedule, fun) do
    check_in_id =
      case Sentry.capture_check_in(
             status: :in_progress,
             monitor_slug: slug,
             monitor_config: [
               schedule: [type: :crontab, value: schedule],
               timezone: "Etc/UTC"
             ]
           ) do
        {:ok, check_in_id} -> check_in_id
        _ -> nil
      end

    status = task(fun)

    opts = [status: status, monitor_slug: slug]
    opts = if check_in_id, do: [{:check_in_id, check_in_id} | opts], else: opts
    Sentry.capture_check_in(opts)

    status
  end

  @doc false
  def run_scheduled(name, fun) when is_binary(name) and is_function(fun, 0) do
    run_scheduled(name, fun, System.get_env("HEXPM_READ_ONLY_MODE") == "1")
  end

  @doc false
  def run_scheduled(name, _fun, true) when is_binary(name) do
    Logger.info("[task] Skipping #{name} in read-only mode")
    :skipped
  end

  def run_scheduled(_name, fun, false) when is_function(fun, 0), do: fun.()

  defp task(fun) do
    Process.flag(:trap_exit, true)

    %Task{ref: ref} =
      Task.async(fn ->
        try do
          fun.()
          :ok
        rescue
          exception ->
            report_error(exception, __STACKTRACE__)
            :error
        end
      end)

    receive do
      {^ref, result} ->
        result

      {:EXIT, _pid, {error, stacktrace}} ->
        exception = Exception.normalize(:error, error, stacktrace)
        report_error(exception, stacktrace)
        :error
    end
  after
    Process.flag(:trap_exit, false)
  end

  defp report_error(exception, stacktrace) do
    Sentry.capture_exception(exception, stacktrace: stacktrace)
    Logger.warning("Sleeping for Sentry to report error")
    Process.sleep(Application.get_env(:hexpm, :sentry_flush_ms, 5000))
  end

  defp start_app() do
    Logger.info("[task] Starting app...")
    Application.put_env(:phoenix, :serve_endpoints, false, persistent: true)
    Application.put_env(:hexpm, :topologies, [], persistent: true)
    {:ok, _} = Application.ensure_all_started(:hexpm)
  end

  defp start_repo() do
    Logger.info("[task] Starting dependencies...")
    start_apps(@repo_apps)
    Logger.info("[task] Starting repos...")

    Enum.each(@repos, fn repo ->
      {:ok, _} = repo.start_link(pool_size: 2)
    end)
  end

  defp stop() do
    Logger.info("[task] Stopping...")
    :init.stop()
  end

  defp run_migrations(args) do
    Enum.each(@repos, fn repo ->
      app = Keyword.get(repo.config(), :otp_app)
      Logger.info("[task] Running migrations for #{app}")

      case args do
        ["--step", n] -> migrate(repo, :up, step: String.to_integer(n))
        ["-n", n] -> migrate(repo, :up, step: String.to_integer(n))
        ["--to", to] -> migrate(repo, :up, to: to)
        ["--all"] -> migrate(repo, :up, all: true)
        [] -> migrate(repo, :up, all: true)
      end
    end)
  end

  defp run_rollback(args) do
    Enum.each(@repos, fn repo ->
      app = Keyword.get(repo.config(), :otp_app)
      Logger.info("[task] Running rollback for #{app}")

      case args do
        ["--step", n] -> migrate(repo, :down, step: String.to_integer(n))
        ["-n", n] -> migrate(repo, :down, step: String.to_integer(n))
        ["--to", to] -> migrate(repo, :down, to: to)
        ["--all"] -> migrate(repo, :down, all: true)
        [] -> migrate(repo, :down, step: 1)
      end
    end)
  end

  defp migrate(repo, direction, opts) do
    migrations_path = priv_path_for(repo, "migrations")
    Ecto.Migrator.run(repo, migrations_path, direction, opts)
  end

  defp run_seeds() do
    Enum.each(@repos, &run_seeds_for/1)
  end

  defp run_seeds_for(repo) do
    # Run the seed script if it exists
    seed_script = priv_path_for(repo, "seeds.exs")

    if File.exists?(seed_script) do
      Logger.info("[task] Running seed script...")
      Code.eval_file(seed_script)
    end
  end

  defp priv_path_for(repo, filename) do
    app = Keyword.get(repo.config(), :otp_app)
    priv_dir = Application.app_dir(app, "priv")

    Path.join([priv_dir, "repo", filename])
  end

  # TODO: Move all scripts to release tasks
  defp run_script(args) do
    [script | args] = args

    priv_dir = Application.app_dir(:hexpm, "priv")
    script_dir = Path.join(priv_dir, "scripts")
    original_argv = System.argv()

    Logger.info("[task] Running #{script} #{inspect(args)}")

    try do
      System.argv(args)
      Code.eval_file(script, script_dir)
    after
      System.argv(original_argv)
    end

    Logger.info("[task] Finished #{script} #{inspect(args)}")
  end

  defp start_apps(apps) do
    Enum.each(apps, fn app ->
      {:ok, _} = Application.ensure_all_started(app)
    end)
  end
end

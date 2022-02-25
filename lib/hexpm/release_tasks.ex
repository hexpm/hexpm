defmodule Hexpm.ReleaseTasks do
  alias Hexpm.ReleaseTasks.{CheckNames, Stats}
  require Logger

  @repo_apps [
    :crypto,
    :ssl,
    :postgrex,
    :ecto_sql
  ]

  @repos Application.compile_env!(:hexpm, :ecto_repos)

  def script(args) do
    {:ok, _} = Application.ensure_all_started(:logger)
    Logger.info("[task] Running script")
    start_app()

    task(fn -> run_script(args) end)

    Logger.info("[task] Finished script")
    stop()
  end

  def check_names() do
    {:ok, _} = Application.ensure_all_started(:logger)
    Logger.info("[task] Running check_names")
    start_app()

    task(&CheckNames.run/0)

    Logger.info("[task] Finished check_names")
    stop()
  end

  def migrate(args \\ []) do
    {:ok, _} = Application.ensure_all_started(:logger)
    Logger.info("[task] Running migrate")
    start_repo()

    task(fn -> run_migrations(args) end)

    Logger.info("[task] Finished migrate")
    stop()
  end

  def rollback(args \\ []) do
    {:ok, _} = Application.ensure_all_started(:logger)
    Logger.info("[task] Running rollback")
    start_repo()

    task(fn -> run_rollback(args) end)

    Logger.info("[task] Finished rollback")
    stop()
  end

  def seed(args \\ []) do
    {:ok, _} = Application.ensure_all_started(:logger)
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
    {:ok, _} = Application.ensure_all_started(:logger)
    Logger.info("[task] Running stats")
    start_app()

    task(&Stats.run/0)

    Logger.info("[task] Finished stats")
    stop()
  end

  defp task(fun) do
    Process.flag(:trap_exit, true)

    %Task{ref: ref} =
      Task.async(fn ->
        try do
          fun.()
        catch
          kind, error ->
            Rollbax.report(kind, error, __STACKTRACE__)
        end
      end)

    receive do
      {^ref, _result} ->
        :ok

      {:EXIT, _pid, {error, stacktrace}} ->
        Rollbax.report(:error, error, stacktrace)
    end
  after
    Process.flag(:trap_exit, false)
  end

  defp start_app() do
    Logger.info("[task] Starting app...")
    Application.put_env(:phoenix, :serve_endpoints, false, persistent: true)
    Application.put_env(:hexpm, :topologies, [], persistent: true)
    {:ok, _} = Application.ensure_all_started(:hexpm)
  end

  defp start_repo() do
    Logger.info("[task] Starting dependencies...")

    Enum.each(@repo_apps, fn app ->
      {:ok, _} = Application.ensure_all_started(app)
    end)

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
end

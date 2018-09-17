defmodule Hexpm.ReleaseTasks do
  alias Hexpm.ReleaseTasks.{CheckNames, Stats}

  @repo_apps [
    :crypto,
    :ssl,
    :postgrex,
    :ecto
  ]

  @repos Application.get_env(:hexpm, :ecto_repos, [])

  def check_names() do
    start_app()
    CheckNames.run()
    stop()
  end

  def migrate() do
    start_repo()
    run_migrations()
    stop()
  end

  def seed() do
    start_repo()
    run_migrations()
    run_seeds()
    stop()
  end

  def stats() do
    start_app()
    Stats.run()
    stop()
  end

  defp start_app() do
    Application.put_env(:phoenix, :serve_endpoints, true)
    {:ok, _} = Application.ensure_all_started(:hexpm)
  end

  defp start_repo() do
    IO.puts("Starting dependencies...")

    Enum.each(@repo_apps, fn app ->
      {:ok, _} = Application.ensure_all_started(app)
    end)

    IO.puts("Starting repos...")

    Enum.each(@repos, fn repo ->
      {:ok, _} = repo.start_link(pool_size: 1)
    end)
  end

  defp stop() do
    IO.puts("Success!")
    :init.stop()
  end

  defp run_migrations() do
    Enum.each(@repos, &run_migrations_for/1)
  end

  defp run_migrations_for(repo) do
    app = Keyword.get(repo.config, :otp_app)
    IO.puts("Running migrations for #{app}")
    migrations_path = priv_path_for(repo, "migrations")
    Ecto.Migrator.run(repo, migrations_path, :up, all: true)
  end

  defp run_seeds() do
    Enum.each(@repos, &run_seeds_for/1)
  end

  defp run_seeds_for(repo) do
    # Run the seed script if it exists
    seed_script = priv_path_for(repo, "seeds.exs")

    if File.exists?(seed_script) do
      IO.puts("Running seed script...")
      Code.eval_file(seed_script)
    end
  end

  defp priv_path_for(repo, filename) do
    app = Keyword.get(repo.config, :otp_app)
    priv_dir = Application.app_dir(app, "priv")

    Path.join([priv_dir, "repo", filename])
  end
end

defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [app: :hex_web,
     version: "0.0.1",
     elixir: "~> 1.2",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases,
     deps: deps]
  end

  def application do
    [mod: {HexWeb, []},
     applications: [:phoenix, :phoenix_html, :cowboy, :logger,
                    :phoenix_ecto, :postgrex, :comeonin, :httpoison, :ex_aws,
                    :sweet_xml, :porcelain, :gen_smtp]]
  end

  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  defp deps do
    [{:phoenix,             "~> 1.1"},
     {:phoenix_ecto,        "~> 2.0"},
     {:postgrex,            ">= 0.0.0"},
     {:phoenix_html,        "~> 2.3"},
     {:cowboy,              "~> 1.0"},
     {:porcelain,           "~> 2.0"},
     {:earmark,             "~> 0.1"},
     {:gen_smtp,            "~> 0.9"},
     {:comeonin,            "~> 2.0"},
     {:httpoison,           "~> 0.7"},
     {:sweet_xml,           "~> 0.5"},
     {:ex_aws,              "~> 0.4"},
     {:phoenix_live_reload, "~> 1.0", only: :dev}]
  end

  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     test: &test/1,
     "app.start": &app_start/1,
     "ecto.create": &ecto_create/1,
     "ecto.drop": &ecto_drop/1,
     "ecto.migrate": &ecto_migrate/1,
     "ecto.rollback": &ecto_rollback/1]
  end

  defp test(args) do
    env([env: :test, level: :error], fn ->
      Mix.Task.run "ecto.drop", ["HexWeb.Repo"]
      Mix.Task.run "ecto.create", ["HexWeb.Repo"]
      Mix.Task.run "ecto.migrate", ["HexWeb.Repo"]
      Mix.Task.reenable "app.start"
      Mix.Task.run "test", args
    end)
  end

  defp app_start(args) do
    Mix.Task.run "app.start", args
    # Work around bug in 1.0 that stops logger even if --no-start is passed
    {:ok, _} = Application.ensure_all_started(:logger)
  end

  defp ecto_create(args) do
    Mix.Task.run "ecto.create", args ++ ["--no-start"]
  end

  defp ecto_drop(args) do
    Mix.Task.run "ecto.drop", args ++ ["--no-start"]
  end

  defp ecto_migrate(args) do
    env([level: :warn], fn ->
      # Workaround for task bug
      Mix.Task.run "app.start", ["--no-start"]
      Mix.Task.run "ecto.migrate", args
    end)
  end

  defp ecto_rollback(args) do
    env([level: :warn], fn ->
      # Workaround for task bug
      Mix.Task.run "app.start", ["--no-start"]
      Mix.Task.run "ecto.rollback", args
    end)
  end

  defp env(opts, fun) do
    old_level = Logger.level
    old_env = Mix.env
    Logger.configure(level: opts[:level])
    if opts[:env], do: Mix.env(opts[:env])

    try do
      fun.()
    after
      # If application start fails we need to restart logger because app.start
      # stops it
      {:ok, _} = Application.ensure_all_started(:logger)
      Logger.configure(level: old_level)
      Mix.env(old_env)
    end
  end
end

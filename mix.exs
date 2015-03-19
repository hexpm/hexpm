defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [app: :hex_web,
     version: "0.0.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases,
     deps: deps]
  end

  def application do
    [applications: [:plug, :cowboy, :ecto, :postgrex, :poison, :bcrypt, :mini_s3,
                    :logger, :porcelain],
     mod: {HexWeb, []},
     env: []]
  end

  defp deps do
    [{:plug,      "~> 0.8"},
     {:cowboy,    "~> 1.0"},
     {:ecto,      "~> 0.4.0"},
     {:postgrex,  ">= 0.0.0"},
     {:poison,    "~> 1.2"},
     {:porcelain, "~> 2.0"},
     {:earmark,   "~> 0.1"},
     {:gen_smtp,  "~> 0.9.0"},
     {:bcrypt,    github: "opscode/erlang-bcrypt"},
     {:mini_s3,   github: "ericmj/mini_s3", branch: "hex-fixes"}
   ]
  end

  defp aliases do
    [test: &test/1,
     "app.start": &app_start/1,
     "ecto.create": &ecto_create/1,
     "ecto.drop": &ecto_drop/1,
     "ecto.migrate": &ecto_migrate/1,
     "ecto.rollback": &ecto_rollback/1]
  end

  defp test(args) do
    env(:test, :warn, fn ->
      Mix.Task.run "ecto.drop", ["HexWeb.Repo"]
      Mix.Task.run "ecto.create", ["HexWeb.Repo"]
      Mix.Task.run "ecto.migrate", ["HexWeb.Repo"]
      HexWeb.Repo.stop
      Mix.Task.reenable "app.start"
      Mix.Task.run "app.start", args
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
    Mix.Task.run "ecto.migrate", ["--no-start" | args]
  end

  defp ecto_rollback(args) do
    Mix.Task.run "ecto.rollback", ["--no-start" | args]
  end

  defp env(env, level, fun) do
    old_level = Logger.level
    old_env = Mix.env
    Logger.configure(level: level)
    Mix.env(env)

    try do
      fun.()
    after
      Logger.configure(level: old_level)
      Mix.env(old_env)
    end
  end
end

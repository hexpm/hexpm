defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [app: :hex_web,
     version: "0.0.1",
     elixir: "~> 1.0",
     aliases: aliases,
     deps: deps]
  end

  def application do
    [applications: [:plug, :cowboy, :ecto, :postgrex, :jazz, :bcrypt, :mini_s3,
                    :logger, :porcelain],
     mod: {HexWeb, []},
     env: []]
  end

  defp deps do
    [{:plug,      github: "elixir-lang/plug"},
     {:ecto,      github: "elixir-lang/ecto"},
     {:jazz,      github: "meh/jazz"},
     {:bcrypt,    github: "opscode/erlang-bcrypt"},
     {:mini_s3,   github: "ericmj/mini_s3", branch: "hex-fixes"},
     {:porcelain, github: "alco/porcelain"},
     {:cowboy,    github: "ninenines/cowboy", tag: "1.0.0", override: true},
     {:cowlib,    github: "ninenines/cowlib", tag: "1.0.0", override: true},
     {:ranch,     github: "ninenines/ranch", tag: "1.0.0", override: true},
     {:poolboy,   github: "devinus/poolboy", override: true},
     {:postgrex,  github: "ericmj/postgrex", override: true},
     {:decimal,   github: "ericmj/decimal", override: true},
     {:earmark,   github: "pragdave/earmark", only: :dev},
     {:gen_smtp,  github: "Vagabond/gen_smtp"}
   ]
  end

  defp aliases do
    [test: &test/1,
     "ecto.migrate": &ecto_migrate/1,
     "ecto.rollback": &ecto_rollback/1]
  end

  defp test(args) do
    Mix.Task.run "ecto.create", ["HexWeb.Repo"]
    Mix.Task.run "ecto.migrate", ["HexWeb.Repo"]
    Mix.Task.run "test", args
  end

  defp ecto_migrate(args) do
    Mix.Task.run "ecto.migrate", ["--no-start" | args]
  end

  defp ecto_rollback(args) do
    Mix.Task.run "ecto.rollback", ["--no-start" | args]
  end
end

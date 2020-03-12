defmodule Hexpm.MixProject do
  use Mix.Project

  def project() do
    [
      app: :hexpm,
      version: "0.0.1",
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      xref: xref(),
      compilers: [:phoenix] ++ Mix.compilers(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      releases: releases(),
      deps: deps()
    ]
  end

  def application() do
    [
      mod: {Hexpm.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp xref() do
    [exclude: [Hex.Registry, Hex.Resolver]]
  end

  defp deps() do
    [
      {:bamboo, "~> 1.0"},
      {:bcrypt_elixir, "~> 2.0"},
      {:corsica, "~> 1.0"},
      {:earmark, "~> 1.0"},
      {:ecto_sql, "~> 3.0"},
      {:ecto, "~> 3.0", override: true},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_ses, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_machina, "~> 2.0"},
      {:eqrcode, "~> 0.1.6"},
      {:goth, "~> 1.2"},
      {:hackney, "~> 1.7"},
      {:hex_core, "~> 0.2", hex_core_opts()},
      {:jason, "~> 1.0"},
      {:libcluster, "~> 3.0"},
      {:logster, "~> 1.0.0"},
      {:mox, "~> 0.5.0", only: :test},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 2.3"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix, "~> 1.4"},
      {:plug_attack, "~> 0.3"},
      {:plug_cowboy, "~> 2.0"},
      {:plug, "~> 1.7"},
      {:postgrex, "~> 0.14"},
      {:pot, "~> 0.10.1"},
      {:rollbax, "~> 0.5"},
      {:sweet_xml, "~> 0.5"}
    ]
  end

  defp hex_core_opts() do
    if path = System.get_env("HEX_CORE_PATH") do
      [path: path]
    else
      []
    end
  end

  defp aliases() do
    [
      setup: ["deps.get", "ecto.setup", &setup_yarn/1],
      "ecto.setup": ["ecto.reset", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  defp releases() do
    [
      hexpm: [
        include_executables_for: [:unix]
      ]
    ]
  end

  defp setup_yarn(_) do
    cmd("yarn", ["install"], cd: "assets")
  end

  defp cmd(cmd, args, opts) do
    opts = Keyword.merge([into: IO.stream(:stdio, :line), stderr_to_stdout: true], opts)
    {_, result} = System.cmd(cmd, args, opts)

    if result != 0 do
      raise "Non-zero result (#{result}) from: #{cmd} #{Enum.map_join(args, " ", &inspect/1)}"
    end
  end
end

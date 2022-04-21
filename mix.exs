defmodule Hexpm.MixProject do
  use Mix.Project

  def project() do
    [
      app: :hexpm,
      version: "0.0.1",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      xref: xref(),
      compilers: Mix.compilers(),
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
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp extra_applications(:test), do: [:logger]
  defp extra_applications(_), do: [:logger, :runtime_tools, :os_mon]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp xref() do
    [exclude: [Hex, Hex.Registry, Hex.Resolver]]
  end

  defp deps() do
    [
      {:bamboo, "~> 2.2"},
      {:bamboo_phoenix, "~> 1.0"},
      {:bcrypt_elixir, "~> 2.0"},
      {:corsica, "~> 1.0"},
      {:earmark, "~> 1.4"},
      {:ecto_sql, "~> 3.0"},
      {:ecto, "~> 3.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_machina, "~> 2.0"},
      {:eqrcode, "~> 0.1.6"},
      {:goth, "~> 1.3-rc"},
      {:hackney, "~> 1.7"},
      {:hex_core, "~> 0.2", hex_core_opts()},
      {:jason, "~> 1.0"},
      {:libcluster, "~> 3.0"},
      {:logster, "~> 1.0"},
      {:mox, "~> 1.0", only: :test},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 3.1"},
      {:phoenix_live_dashboard, "~> 0.6"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix, "~> 1.6"},
      {:plug_attack, "~> 0.3"},
      {:plug_cowboy, "~> 2.1"},
      {:plug, "~> 1.7"},
      {:postgrex, "~> 0.14"},
      {:pot, "~> 1.0"},
      {:rollbax, "~> 0.5"},
      {:sweet_xml, "~> 0.5"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetry_metrics, "~> 0.6"}
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
      setup: ["deps.get", "ecto.setup", "cmd yarn install --cwd assets"],
      "ecto.setup": ["ecto.reset", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  defp releases() do
    [
      hexpm: [
        include_executables_for: [:unix],
        reboot_system_after_config: true
      ]
    ]
  end
end

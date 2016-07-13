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
     aliases: aliases(),
     deps: deps()]
  end

  def application do
    [mod: {HexWeb, []},
     applications: apps(Mix.env)]
  end

  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  defp deps do
    [{:phoenix,             "~> 1.2.0-rc"},
     {:phoenix_ecto,        "~> 3.0.0"},
     {:ecto,                "~> 2.0"},
     {:phoenix_html,        "~> 2.3"},
     {:postgrex,            ">= 0.0.0"},
     {:cowboy,              "~> 1.0"},
     {:porcelain,           "~> 2.0"},
     {:earmark,             "~> 1.0"},
     {:gen_smtp,            "~> 0.9"},
     {:comeonin,            "~> 2.0"},
     {:httpoison,           "~> 0.8"},
     {:sweet_xml,           "~> 0.5"},
     {:ex_aws,              "~> 0.4"},
     {:jiffy,               "~> 0.14"},
     {:rollbax,             "~> 0.5"},
     {:phoenix_live_reload, "~> 1.0", only: :dev}]
  end

  defp apps(:prod), do: apps(:other) ++ [:rollbax]

  defp apps(_) do
    [:phoenix,
     :phoenix_html,
     :cowboy,
     :logger,
     :phoenix_ecto,
     :postgrex,
     :comeonin,
     :httpoison,
     :ex_aws,
     :sweet_xml,
     :porcelain,
     :gen_smtp,
     :jiffy]
  end

  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
     "test": ["ecto.migrate", "test"]]
  end
end

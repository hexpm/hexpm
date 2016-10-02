defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [app: :hex_web,
     version: "0.0.1",
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     gpb_options: gpb_options(),
     xref: xref(),
     compilers: [:phoenix, :gpb] ++ Mix.compilers,
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

  defp gpb_options do
    [verify: :always,
     strings_as_binaries: true,
     maps: true,
     maps_unset_optional: :omitted,
     report_warnings: true,
     target_erlang_version: 18]
  end

  defp xref do
    [exclude: [{Hex.Registry, :prefetch, 1}]]
  end

  defp deps do
    [{:phoenix,             "~> 1.2"},
     {:phoenix_ecto,        "~> 3.1-rc"},
     {:phoenix_html,        "~> 2.3"},
     {:postgrex,            ">= 0.0.0"},
     {:cowboy,              "~> 1.0"},
     {:porcelain,           "~> 2.0"},
     {:earmark,             "~> 1.0"},
     {:bamboo,              "~> 0.7"},
     {:bamboo_smtp,         "~> 1.2"},
     {:comeonin,            "~> 2.0"},
     {:httpoison,           "~> 0.8"},
     {:sweet_xml,           "~> 0.5"},
     {:ex_aws,              "~> 0.4"},
     {:jiffy,               "~> 0.14"},
     {:rollbax,             "~> 0.5"},
     {:gpb,                 "~> 3.23"},
     {:plug,                "~> 1.2"},
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
     :jiffy,
     :bamboo,
     :bamboo_smtp]
  end

  defp aliases do
    ["compile.gpb": &compile_gpb/1,
     "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
     "test": ["ecto.migrate", "test"]]
  end

  defp compile_gpb(args) do
    alias Mix.Compilers.Erlang
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])

    project     = Mix.Project.config
    proto_paths = project[:proto_paths] || ["proto"]
    erlc_path   = project[:erlc_paths] |> List.first
    mappings    = Enum.zip(proto_paths, Stream.repeatedly(fn -> erlc_path end))
    options     = project[:gpb_options] || []
    options     = options ++ [o: erlc_path]
    manifest    = Path.join(Mix.Project.manifest_path, ".compile.gpb")

    Erlang.compile(manifest, mappings, :proto, :erl, opts, fn
      input, output ->
        Erlang.ensure_application!(:gpb, input)

        file        = Path.basename(input)
        import_path = input |> Path.relative_to_cwd |> Path.dirname
        options     = options ++ [i: import_path]

        case :gpb_compile.file(Erlang.to_erl_file(file), options) do
          :ok -> {:ok, output}
          {:error, _} -> :error
        end
    end)
  end
end

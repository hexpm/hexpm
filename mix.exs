defmodule Hexpm.MixProject do
  use Mix.Project

  def project() do
    [
      app: :hexpm,
      version: "0.0.1",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      gpb_options: gpb_options(),
      xref: xref(),
      compilers: [:phoenix, :gpb] ++ Mix.compilers(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application() do
    [
      mod: {Hexpm.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support/fake.ex", "test/support/factory.ex"]
  defp elixirc_paths(_), do: ["lib"]

  defp gpb_options() do
    [
      verify: :always,
      strings_as_binaries: true,
      maps: true,
      maps_unset_optional: :omitted,
      report_warnings: true,
      target_erlang_version: 18
    ]
  end

  defp xref() do
    [exclude: [Hex.Registry, Hex.Resolver]]
  end

  defp deps() do
    [
      {:bamboo, "~> 0.7"},
      {:bcrypt_elixir, "~> 1.0"},
      {:corsica, "~> 1.0"},
      {:cowboy, "~> 1.0"},
      {:earmark, "~> 1.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_ses, "~> 2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_machina, "~> 2.0"},
      {:gpb, "~> 3.23"},
      {:hackney, "~> 1.7"},
      {:jiffy, "~> 0.14"},
      {:mox, "~> 0.3.1", only: :test},
      {:phoenix_ecto, "~> 3.1"},
      {:phoenix_html, "~> 2.3"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:phoenix, "~> 1.3"},
      {:plug_attack, "~> 0.3"},
      {:plug, "~> 1.2"},
      {:porcelain, "~> 2.0"},
      {:postgrex, ">= 0.0.0"},
      {:rollbax, "~> 0.5", only: :prod},
      {:sbroker, "~> 1.0"},
      {:sweet_xml, "~> 0.5"}
    ]
  end

  defp aliases() do
    [
      "compile.gpb": &compile_gpb/1,
      "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
      "ecto.setup": ["ecto.drop", "ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      test: ["ecto.migrate", "test"]
    ]
  end

  defp compile_gpb(args) do
    alias Mix.Compilers.Erlang
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])

    project = Mix.Project.config()
    proto_paths = project[:proto_paths] || ["priv/proto"]
    erlc_path = project[:erlc_paths] |> List.first()
    mappings = Enum.zip(proto_paths, Stream.repeatedly(fn -> erlc_path end))
    options = project[:gpb_options] || []
    options = options ++ [o: erlc_path]
    manifest = Path.join(Mix.Project.manifest_path(), ".compile.gpb")

    Erlang.compile(manifest, mappings, :proto, :erl, opts, fn input, output ->
      Erlang.ensure_application!(:gpb, input)

      file = Path.basename(input)
      import_path = input |> Path.relative_to_cwd() |> Path.dirname()
      options = options ++ [i: import_path]

      case :gpb_compile.file(Erlang.to_erl_file(file), options) do
        :ok -> {:ok, output}
        {:error, _} -> :error
      end
    end)
  end
end

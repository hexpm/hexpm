defmodule Mix.Tasks.Hexpm.LumisCache do
  @moduledoc """
  Downloads and compiles parsers for syntax highlighting into `priv/lumis`,
  so `lumis serve` has them from the start.

      mix hexpm.lumis_cache [LANGUAGE...]

  Without arguments it caches `:prefetch_languages` from
  `config :hexpm, HexpmWeb.SyntaxHighlight`. Languages already cached are not
  downloaded again.
  """

  use Mix.Task

  @shortdoc "Downloads the parsers syntax highlighting starts with"

  @data_dir "priv/lumis"

  @requirements ["compile"]

  @impl Mix.Task
  def run(args) do
    languages =
      case args do
        [] -> Application.fetch_env!(:hexpm, HexpmWeb.SyntaxHighlight)[:prefetch_languages]
        languages -> languages
      end

    Mix.shell().info("Caching #{Enum.join(languages, ", ")} in #{@data_dir}")

    case Lumis.Port.cache(languages, data_dir: Path.expand(@data_dir)) do
      :ok -> :ok
      {:error, output} -> Mix.raise("Failed to cache parsers:\n#{output}")
    end
  end
end

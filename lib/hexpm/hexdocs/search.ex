defmodule Hexpm.Hexdocs.Search do
  require Logger

  @callback index(String.t(), Version.t() | String.t(), String.t(), [map]) :: :ok
  @callback delete(String.t(), Version.t() | String.t()) :: :ok

  def index(package, version, proglang, items),
    do: impl().index(package, version, proglang, items)

  def delete(package, version), do: impl().delete(package, version)

  def find_search_items(package, version, files) do
    search_data_js =
      Enum.find_value(files, fn {path, content} ->
        if String.starts_with?(Path.basename(path), "search_data-"), do: content
      end)

    unless search_data_js, do: Logger.info("Failed to find search data for #{package} #{version}")

    search_data =
      case search_data_js do
        "searchData=" <> json ->
          case JSON.decode(json) do
            {:ok, data} ->
              data

            {:error, reason} ->
              raise "Failed to decode search data json for #{package} #{version}: #{inspect(reason)}"
          end

        data when is_binary(data) ->
          raise "Unexpected search_data format for #{package} #{version}"

        nil ->
          nil
      end

    case search_data do
      %{"items" => [_ | _] = items} ->
        {Map.get(search_data, "proglang") || proglang(items), items}

      %{"items" => []} ->
        nil

      nil ->
        nil

      _ ->
        raise "Failed to extract search items and proglang from search data for #{package} #{version}"
    end
  end

  defp proglang(items) do
    if Enum.any?(items, &elixir_module?/1), do: "elixir", else: "erlang"
  end

  defp elixir_module?(%{"type" => "module", "title" => <<first, _::binary>>})
       when first in ?A..?Z,
       do: true

  defp elixir_module?(_item), do: false
  defp impl, do: Application.fetch_env!(:hexpm, :hexdocs_search_impl)
end

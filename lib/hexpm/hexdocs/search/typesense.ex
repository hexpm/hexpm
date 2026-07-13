defmodule Hexpm.Hexdocs.Search.Typesense do
  @behaviour Hexpm.Hexdocs.Search
  @timeout 60_000

  @impl true
  def index(package, version, proglang, search_items) do
    full_package = "#{package}-#{version}"

    ndjson =
      Enum.map(search_items, fn item ->
        json =
          item
          |> Map.take(["type", "ref", "title", "doc"])
          |> Map.update("doc", "", &(&1 || ""))
          |> Map.put("package", full_package)
          |> Map.put("proglang", proglang)
          |> Jason.encode!()

        [json, ?\n]
      end)

    url = url("collections/#{collection()}/documents/import?action=create")
    headers = [{"x-typesense-api-key", api_key()}]

    case request(url, fn ->
           Hexpm.HTTP.impl().post(url, headers, ndjson, receive_timeout: @timeout)
         end) do
      {:ok, 200, _headers, body} ->
        body
        |> IO.iodata_to_binary()
        |> String.split("\n", trim: true)
        |> Enum.zip(search_items)
        |> Enum.each(fn {response, item} ->
          case Jason.decode!(response) do
            %{"success" => true} ->
              :ok

            %{"success" => false, "error" => error} ->
              raise "Failed to index search item #{inspect(item)} for #{package} #{version}: #{inspect(error)}"
          end
        end)

      {:ok, status, _headers, _body} ->
        raise "Failed to index search items for #{package} #{version}: status=#{status}"

      {:error, reason} ->
        raise "Failed to index search items #{package} #{version}: #{inspect(reason)}"
    end
  end

  @impl true
  def delete(package, version) do
    query = URI.encode_query([{"filter_by", "package:#{package}-#{version}"}])
    url = url("collections/#{collection()}/documents?" <> query)
    headers = [{"x-typesense-api-key", api_key()}]

    case request(url, fn -> Hexpm.HTTP.impl().delete(url, headers, receive_timeout: @timeout) end) do
      {:ok, 200, _headers, _body} ->
        :ok

      {:ok, status, _headers, _body} ->
        raise "Failed to delete search items for #{package} #{version}: status=#{status}"

      {:error, reason} ->
        raise "Failed to delete search items for #{package} #{version}: #{inspect(reason)}"
    end
  end

  def collection, do: Application.fetch_env!(:hexpm, :hexdocs_typesense_collection)
  def api_key, do: Application.fetch_env!(:hexpm, :hexdocs_typesense_api_key)

  def collection_schema(collection \\ collection()) do
    %{
      "fields" => [
        %{"facet" => true, "name" => "proglang", "type" => "string"},
        %{"facet" => true, "name" => "type", "type" => "string"},
        %{"name" => "title", "type" => "string", "token_separators" => separators()},
        %{"name" => "doc", "type" => "string", "token_separators" => separators()},
        %{"facet" => true, "name" => "package", "type" => "string"}
      ],
      "name" => collection
    }
  end

  defp separators, do: [".", "_", "-", "*", "`", ":", "@", "/"]
  defp url(path), do: Path.join(Application.fetch_env!(:hexpm, :hexdocs_typesense_url), path)

  defp request(url, fun) do
    Hexpm.HTTP.retry(fun, "typesense #{url}",
      attempts: 5,
      base_delay: 200,
      statuses: [429, 500..599]
    )
  end
end

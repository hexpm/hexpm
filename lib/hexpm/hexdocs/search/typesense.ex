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
          |> Map.update("type", "", &(&1 || ""))
          |> Map.update("doc", "", &(&1 || ""))
          |> Map.put("package", full_package)
          |> Map.put("proglang", proglang)
          |> JSON.encode!()

        [json, ?\n]
      end)

    url = url("collections/#{collection()}/documents/import?action=create")
    headers = [{"x-typesense-api-key", api_key()}]

    case request(:post, url, fn ->
           Hexpm.HTTP.impl().post(url, headers, ndjson, receive_timeout: @timeout)
         end) do
      {:ok, status, _headers, body} ->
        body = IO.iodata_to_binary(body)
        check_rejected!(body, package, version)

        if status != 200 do
          raise "Failed to index search items for #{package} #{version}: " <>
                  "status=#{status} body=#{excerpt(body)}"
        end

        body
        |> String.split("\n", trim: true)
        |> Enum.zip(search_items)
        |> Enum.each(fn {response, item} ->
          case JSON.decode(response) do
            {:ok, %{"success" => true}} ->
              :ok

            {:ok, %{"success" => false, "error" => error}} ->
              raise "Failed to index search item #{inspect(item)} for #{package} #{version}: #{inspect(error)}"

            _other ->
              raise "Unexpected import response for #{package} #{version}: #{excerpt(response)}"
          end
        end)

      {:error, reason} ->
        raise "Failed to index search items #{package} #{version}: #{inspect(reason)}"
    end
  end

  # Typesense refuses writes while a node is short on memory or disk. A request
  # it refuses outright gets a 422. When the refusal hits a later chunk of an
  # import that already started answering, the 200 response carries the
  # refusal after the results of the earlier chunks.
  defp check_rejected!(body, package, version) do
    if body =~ "Rejecting write" do
      raise Hexpm.Hexdocs.Search.WriteRejectedError,
        message: "Typesense rejected the search items for #{package} #{version}: #{excerpt(body)}"
    end
  end

  # The end of the body, where a refusal lands in an import response.
  defp excerpt(body), do: String.slice(body, -500, 500)

  @impl true
  def delete(package, version) do
    query = URI.encode_query([{"filter_by", "package:#{package}-#{version}"}])
    url = url("collections/#{collection()}/documents?" <> query)
    headers = [{"x-typesense-api-key", api_key()}]

    case request(:delete, url, fn ->
           Hexpm.HTTP.impl().delete(url, headers, receive_timeout: @timeout)
         end) do
      {:ok, 200, _headers, _body} ->
        :ok

      {:ok, status, _headers, body} ->
        raise "Failed to delete search items for #{package} #{version}: " <>
                "status=#{status} body=#{excerpt(IO.iodata_to_binary(body))}"

      {:error, reason} ->
        raise "Failed to delete search items for #{package} #{version}: #{inspect(reason)}"
    end
  end

  defp collection, do: Application.fetch_env!(:hexpm, :hexdocs_typesense_collection)
  defp api_key, do: Application.fetch_env!(:hexpm, :hexdocs_typesense_api_key)
  defp url(path), do: Path.join(Application.fetch_env!(:hexpm, :hexdocs_typesense_url), path)

  defp request(method, url, fun) do
    Hexpm.HTTP.track_request(method, url, fn ->
      Hexpm.HTTP.retry(fun, "typesense #{url}",
        attempts: 5,
        base_delay: 200,
        statuses: [429, 500..599]
      )
    end)
  end
end

defmodule Hexpm.Store.GCS do
  import SweetXml, only: [sigil_x: 2]
  require Logger

  @behaviour Hexpm.Store

  @gs_xml_url "https://storage.googleapis.com"

  def list(bucket, prefix) do
    list_stream(bucket, prefix)
  end

  def get(bucket, key, _opts) do
    url = url(bucket, key)

    case Hexpm.HTTP.retry(fn -> Hexpm.HTTP.get(url, headers()) end, "gcs") do
      {:ok, 200, _headers, body} -> body
      _ -> nil
    end
  end

  def put(bucket, key, blob, opts) do
    headers =
      headers() ++
        meta_headers(Keyword.fetch!(opts, :meta)) ++
        [
          {"cache-control", Keyword.fetch!(opts, :cache_control)},
          {"content-type", Keyword.get(opts, :content_type)}
        ]

    url = url(bucket, key)
    headers = filter_nil_values(headers)

    {:ok, 200, _headers, _body} =
      Hexpm.HTTP.retry(fn -> Hexpm.HTTP.put(url, headers, blob) end, "gcs")

    :ok
  end

  def delete_many(bucket, keys) do
    keys
    |> Task.async_stream(
      &delete(bucket, &1),
      max_concurrency: 10,
      timeout: 10_000
    )
    |> Stream.run()
  end

  def delete(bucket, key) do
    url = url(bucket, key)

    {:ok, 204, _headers, _body} =
      Hexpm.HTTP.retry(fn -> Hexpm.HTTP.delete(url, headers()) end, "gcs")

    :ok
  end

  defp list_stream(bucket, prefix) do
    start_fun = fn -> nil end
    after_fun = fn _ -> nil end

    next_fun = fn
      :halt ->
        {:halt, nil}

      marker ->
        {items, marker} = do_list(bucket, prefix, marker)
        {items, marker || :halt}
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  defp do_list(bucket, prefix, marker) do
    url = url(bucket) <> "?prefix=#{prefix}&marker=#{marker}"

    {:ok, 200, _headers, body} = Hexpm.HTTP.retry(fn -> Hexpm.HTTP.get(url, headers()) end, "gcs")

    doc = SweetXml.parse(body)
    marker = SweetXml.xpath(doc, ~x"/ListBucketResult/NextMarker/text()"s)
    items = SweetXml.xpath(doc, ~x"/ListBucketResult/Contents/Key/text()"ls)
    marker = if marker != "", do: marker

    {items, marker}
  end

  defp filter_nil_values(keyword) do
    Enum.reject(keyword, fn {_key, value} -> is_nil(value) end)
  end

  defp headers() do
    {:ok, token} = Goth.fetch(Hexpm.Goth)
    [{"authorization", "#{token.type} #{token.token}"}]
  end

  defp meta_headers(meta) do
    Enum.map(meta, fn {key, value} ->
      {"x-goog-meta-#{key}", value}
    end)
  end

  defp url(bucket) do
    @gs_xml_url <> "/" <> bucket
  end

  defp url(bucket, key) do
    url(bucket) <> "/" <> key
  end
end

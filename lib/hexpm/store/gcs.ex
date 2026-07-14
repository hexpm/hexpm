defmodule Hexpm.Store.GCS do
  import SweetXml, only: [sigil_x: 2]
  require Logger

  @behaviour Hexpm.Store.Behaviour

  @default_gs_xml_url "https://storage.googleapis.com"

  def list(bucket, prefix) do
    list_stream(bucket, prefix)
  end

  def get(bucket, key, _opts) do
    url = url(bucket, key)

    case Hexpm.HTTP.retry(fn -> Hexpm.HTTP.impl().get(url, headers()) end, "gcs") do
      {:ok, 200, _headers, body} -> body
      _ -> nil
    end
  end

  def get_to_file(bucket, key, destination, opts) do
    case get(bucket, key, opts) do
      nil -> nil
      body -> File.write!(destination, body)
    end
  end

  def put_file(bucket, key, path, opts) do
    upload(bucket, key, opts, fn url, headers ->
      Hexpm.HTTP.impl().put_file(url, headers, path, [])
    end)
  end

  def put(bucket, key, blob, opts) do
    upload(bucket, key, opts, fn url, headers ->
      Hexpm.HTTP.impl().put(url, headers, blob)
    end)
  end

  defp upload(bucket, key, opts, fun) do
    headers =
      headers() ++
        meta_headers(Keyword.fetch!(opts, :meta)) ++
        [
          {"cache-control", Keyword.fetch!(opts, :cache_control)},
          {"content-type", Keyword.get(opts, :content_type)}
        ]

    url = url(bucket, key)
    headers = filter_nil_values(headers)

    {:ok, 200, _headers, _body} = retry(url, fn -> fun.(url, headers) end)

    :ok
  end

  def delete_many(bucket, keys) do
    keys
    |> Task.async_stream(
      &delete(bucket, &1),
      max_concurrency: 10,
      timeout: 10_000
    )
    |> Stream.each(fn
      {:ok, _result} -> :ok
      {:exit, reason} -> exit(reason)
    end)
    |> Stream.run()
  end

  def delete(bucket, key) do
    url = url(bucket, key)

    case retry(url, fn -> Hexpm.HTTP.impl().delete(url, headers()) end) do
      {:ok, status, _headers, _body} when status in [204, 404] -> :ok
    end
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
    query = URI.encode_query(%{"prefix" => prefix, "marker" => marker || ""})
    url = url(bucket) <> "?" <> query

    {:ok, 200, _headers, body} = retry(url, fn -> Hexpm.HTTP.impl().get(url, headers()) end)

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
    case Application.get_env(:hexpm, :gcs_auth) do
      nil ->
        token = Goth.fetch!(Hexpm.Goth)
        [{"authorization", "#{token.type} #{token.token}"}]

      {module, function} ->
        apply(module, function, [])
    end
  end

  defp meta_headers(meta) do
    Enum.map(meta, fn {key, value} ->
      {"x-goog-meta-#{key}", value}
    end)
  end

  defp url(bucket) do
    Application.get_env(:hexpm, :gcs_url, @default_gs_xml_url) <> "/" <> bucket
  end

  defp url(bucket, key) do
    encoded = URI.encode(key, &(&1 == ?/ or URI.char_unreserved?(&1)))
    url(bucket) <> "/" <> encoded
  end

  defp retry(url, fun) do
    Hexpm.HTTP.retry(fun, "gcs #{url}",
      attempts: 5,
      base_delay: 200,
      statuses: [429, 500..599]
    )
  end
end

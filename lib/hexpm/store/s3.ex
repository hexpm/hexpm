defmodule Hexpm.Store.S3 do
  @behaviour Hexpm.Store

  alias ExAws.S3

  def list(region, bucket, prefix) do
    S3.list_objects(bucket(bucket), prefix: prefix)
    |> ExAws.stream!(region: region(region))
    |> Stream.map(&Map.get(&1, :key))
  end

  def get(region, bucket, key, opts) do
    S3.get_object(bucket(bucket), key, opts)
    |> ExAws.request(region: region(region))
    |> case do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def get_many(region, bucket, keys, opts) do
    opts = default_opts(opts)
    Hexpm.Parallel.each!(&get(region, bucket, &1, opts), keys, opts)
  end

  def get_each(region, bucket, keys, fun, opts) when is_list(keys) do
    opts = default_opts(opts)
    task = &fun.(&1, get(region, bucket, &1, opts))
    Hexpm.Parallel.each!(task, keys, opts)
  end

  # TODO: Add mapping function that runs inside the async processes
  def get_reduce(region, bucket, keys, acc, fun, opts) when is_list(keys) do
    opts = default_opts(opts)
    task = &{&1, get(region, bucket, &1, opts)}
    reducer = &reduce(&1, &2, fun)
    Hexpm.Parallel.reduce!(task, keys, acc, reducer, opts)
  end

  defp reduce({key, body}, acc, fun), do: fun.(key, body, acc)

  # TODO: verify cache-control, surrogate-key and purge for everything we upload
  def put(region, bucket, key, blob, opts) do
    S3.put_object(bucket(bucket), key, blob, opts)
    |> ExAws.request!(region: region(region))

    :ok
  end

  def put_many(region, bucket, values, opts) do
    opts = default_opts(opts)
    Hexpm.Parallel.each!(fn {key, blob, opts} ->
      put(region, bucket, key, blob, opts)
    end, values, opts)
  end

  def put_multipart_init(region, bucket, key, opts) do
    S3.initiate_multipart_upload(bucket(bucket), key, opts)
    |> ExAws.request(region: region(region))
    |> ok
    |> get_in([:body, :upload_id])
  end

  def put_multipart_part(region, bucket, key, upload_id, part_number, blob) do
    S3.upload_part(bucket(bucket), key, upload_id, part_number, blob)
    |> ExAws.request(region: region(region))
    |> ok
    |> Map.fetch!(:headers)
    |> List.keyfind("ETag", 0)
    |> elem(1)
  end

  def put_multipart_complete(region, bucket, key, upload_id, parts) do
    S3.complete_multipart_upload(bucket(bucket), key, upload_id, parts)
    |> ExAws.request(region: region(region))
    |> ok
  end

  defp ok({:ok, result}), do: result

  def delete(region, bucket, key, _opts) do
    S3.delete_object(bucket(bucket), key)
    |> ExAws.request(region: region(region))

    :ok
  end

  def delete_many(region, bucket, keys, opts) do
    case Enum.chunk(keys, 1000, 1000, []) do
      [keys] ->
        delete_mutiple(region, bucket, keys)
      chunks ->
        opts = default_opts(opts)
        Hexpm.Parallel.each!(&delete_mutiple(region, bucket, &1), chunks, opts)
    end
  end

  defp delete_mutiple(region, bucket, keys) do
    {:ok, _} =
      S3.delete_multiple_objects(bucket(bucket), keys)
      |> ExAws.request(region: region(region))
    :ok
  end

  defp bucket(atom) when is_atom(atom),
    do: Application.get_env(:hexpm, atom)
  defp bucket(binary) when is_binary(binary),
    do: binary

  defp region(nil),
    do: "us-east-1"
  defp region(binary) when is_binary(binary),
    do: binary

  defp default_opts(opts) do
    opts
    |> Keyword.put_new(:timeout, :infinity)
    |> Keyword.put_new(:parallel, 10)
  end
end

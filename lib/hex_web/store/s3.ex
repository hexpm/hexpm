defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store

  alias ExAws.S3
  alias ExAws.S3.Impl, as: S3Impl

  def list(region, bucket, prefix) do
    S3.new(region: region(region))
    |> S3Impl.stream_objects!(bucket(bucket), prefix: prefix)
    |> Stream.map(&Map.get(&1, :key))
  end

  def get(region, bucket, keys, opts) when is_list(keys) do
    opts = default_opts(opts)
    HexWeb.Parallel.run!(&get(region, bucket, &1, opts), keys, opts)
  end
  def get(region, bucket, key, _opts) do
    s3 = S3.new(region: region(region))
    case S3Impl.get_object(s3, bucket(bucket), key) do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  # TODO: verify cache-control, surrogate-key and purge for everything we upload
  def put(region, bucket, values, opts) when is_list(values) do
    opts = default_opts(opts)
    HexWeb.Parallel.run!(&put(region, bucket, &1), values, opts)
  end

  defp put(region, bucket, {key, blob, opts}) do
    put(region, bucket, key, blob, opts)
  end

  def put(region, bucket, key, blob, opts) do
    S3.new(region: region(region))
    |> S3Impl.put_object!(bucket(bucket), key, blob, opts)
    :ok
  end

  def delete(region, bucket, keys, opts) when is_list(keys) do
    case Enum.chunk(keys, 1000) do
      [keys] ->
        delete_mutiple(region, bucket, keys)
      chunks ->
        opts = default_opts(opts)
        HexWeb.Parallel.run!(&delete_mutiple(region, bucket, &1), chunks, opts)
    end
  end
  def delete(region, bucket, key, _opts) do
    S3.new(region: region(region))
    |> S3Impl.delete_object!(bucket(bucket), key)
    :ok
  end

  defp delete_mutiple(region, bucket, keys) do
    {:ok, _} =
      S3.new(region: region(region))
      |> S3Impl.delete_multiple_objects(bucket(bucket), keys)
    :ok
  end

  defp bucket(atom) when is_atom(atom),
    do: Application.get_env(:hex_web, atom)
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

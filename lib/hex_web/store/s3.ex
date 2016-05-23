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
    HexWeb.Parallel.run!(&get(region, bucket, &1, opts), keys,
                         timeout: :infinity, parallel: opts[:parallel] || 100)
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
    HexWeb.Parallel.run!(&put(region, bucket, &1), values,
                         timeout: :infinity, parallel: opts[:parallel] || 100)
  end

  defp put(region, bucket, {key, blob, opts}) do
    put(region, bucket, key, blob, opts)
  end

  def put(region, bucket, key, blob, opts) do
    S3.new(region: region(region))
    |> S3Impl.put_object!(bucket(bucket), key, blob, opts)
  end

  def delete(region, bucket, keys, opts) when is_list(keys) do
    HexWeb.Parallel.run!(&delete(region, bucket, &1, opts), keys,
                         timeout: :infinity, parallel: opts[:parallel] || 100)
  end
  def delete(region, bucket, key, _opts) do
    S3.new(region: region(region))
    |> S3Impl.delete_object!(bucket(bucket), key)
  end

  defp bucket(atom) when is_atom(atom),
    do: Application.get_env(:hex_web, atom)
  defp bucket(binary) when is_binary(binary),
    do: binary

  defp region(nil),
    do: "us-east-1"
  defp region(binary) when is_binary(binary),
    do: binary
end

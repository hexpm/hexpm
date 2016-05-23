defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store

  alias ExAws.S3
  alias ExAws.S3.Impl, as: S3Impl

  def list(region, bucket, prefix) do
    S3.new(region: region(region))
    |> S3Impl.stream_objects!(bucket(bucket), prefix: prefix)
    |> Stream.map(&Map.get(&1, :key))
  end

  def get(region, bucket, key) do
    s3 = S3.new(region: region(region))
    case S3Impl.get_object(s3, bucket(bucket), key) do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  # TODO: verify cache-control, surrogate-key and purge for everything we upload
  def put(region, bucket, key, blob, opts) do
    S3.new(region: region(region))
    |> S3Impl.put_object!(bucket(bucket), key, blob, opts)
  end

  def delete(region, bucket, path) do
    S3.new(region: region(region))
    |> S3Impl.delete_object!(bucket(bucket), path)
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

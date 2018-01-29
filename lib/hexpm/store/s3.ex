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

  def put(region, bucket, key, blob, opts) do
    S3.put_object(bucket(bucket), key, blob, opts)
    |> ExAws.request!(region: region(region))
  end

  def delete(region, bucket, key) do
    S3.delete_object(bucket(bucket), key)
    |> ExAws.request!(region: region(region))
  end

  def delete_many(region, bucket, keys) do
    # AWS doesn't like concurrent delete requests
    keys
    |> Stream.chunk_every(1000, 1000, [])
    |> Enum.each(fn chunk ->
      S3.delete_multiple_objects(bucket(bucket), chunk)
      |> ExAws.request!(region: region(region))
    end)
  end

  defp bucket(atom) when is_atom(atom) do
    Application.get_env(:hexpm, atom)
  end

  defp bucket(binary) when is_binary(binary) do
    binary
  end

  defp region(nil) do
    "us-east-1"
  end

  defp region(binary) when is_binary(binary) do
    binary
  end
end

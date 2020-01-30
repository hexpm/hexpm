defmodule Hexpm.Store.S3 do
  @behaviour Hexpm.Store

  alias ExAws.S3

  def list(bucket, prefix) do
    S3.list_objects(bucket(bucket), prefix: prefix)
    |> ExAws.stream!(region: region(bucket))
    |> Stream.map(&Map.get(&1, :key))
  end

  def get(bucket, key, opts) do
    S3.get_object(bucket(bucket), key, opts)
    |> ExAws.request(region: region(bucket))
    |> case do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def put(bucket, key, blob, opts) do
    S3.put_object(bucket(bucket), key, blob, opts)
    |> ExAws.request!(region: region(bucket))
  end

  def delete(bucket, key) do
    S3.delete_object(bucket(bucket), key)
    |> ExAws.request!(region: region(bucket))
  end

  def delete_many(bucket, keys) do
    # AWS doesn't like concurrent delete requests
    keys
    |> Stream.chunk_every(1000, 1000, [])
    |> Enum.each(fn chunk ->
      S3.delete_multiple_objects(bucket(bucket), chunk)
      |> ExAws.request!(region: region(bucket))
    end)
  end

  defp bucket(binary) when is_binary(binary) do
    Enum.at(String.split(binary, ",", parts: 2), 1)
  end

  defp region(binary) when is_binary(binary) do
    Enum.at(String.split(binary, ",", parts: 2), 0)
  end
end

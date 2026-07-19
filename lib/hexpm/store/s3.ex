defmodule Hexpm.Store.S3 do
  @behaviour Hexpm.Store.Behaviour

  alias ExAws.S3

  def list(bucket, prefix) do
    S3.list_objects(bucket(bucket), prefix: prefix)
    |> ExAws.stream!(region: region(bucket))
    |> Stream.map(&Map.get(&1, :key))
  end

  def list_with_sizes(bucket, prefix) do
    S3.list_objects(bucket(bucket), prefix: prefix)
    |> ExAws.stream!(region: region(bucket))
    |> Stream.map(&{Map.fetch!(&1, :key), Map.fetch!(&1, :size)})
  end

  def get(bucket, key, opts) do
    S3.get_object(bucket(bucket), key, opts)
    |> ExAws.request(region: region(bucket))
    |> case do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def size(bucket, key) do
    S3.head_object(bucket(bucket), key)
    |> ExAws.request(region: region(bucket))
    |> case do
      {:ok, %{headers: headers}} -> content_length!(headers)
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def get_to_file(bucket, key, destination, _opts) do
    case size(bucket, key) do
      nil ->
        nil

      _size ->
        S3.download_file(bucket(bucket), key, destination)
        |> ExAws.request(region: region(bucket))
        |> case do
          {:ok, _result} -> :ok
          {:error, exception} when is_exception(exception) -> raise exception
          {:error, reason} -> raise "S3 download failed: #{inspect(reason)}"
        end
    end
  end

  def put(bucket, key, blob, opts) do
    S3.put_object(bucket(bucket), key, blob, opts)
    |> ExAws.request!(region: region(bucket))
  end

  def put_file(bucket, key, path, opts) do
    path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket(bucket), key, opts)
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

  defp content_length!(headers) do
    headers
    |> Enum.find(fn {key, _value} -> String.downcase(key) == "content-length" end)
    |> case do
      {_key, value} when is_binary(value) -> String.to_integer(value)
      {_key, [value | _]} -> String.to_integer(value)
      nil -> raise "S3 response is missing content-length"
    end
  end
end

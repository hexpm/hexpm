defmodule Hexpm.Store.Azure do
  @moduledoc """
  A storage backend for Azure, utilizing blob storage.
  """
  @behaviour Hexpm.Store.Behaviour

  import SweetXml
  alias Azurex.Blob

  # 5k is the default (and the maximum) number of blobs allowed to be returned by the Azure Blob REST API
  # at one time. See https://learn.microsoft.com/en-us/rest/api/storageservices/list-blobs?tabs=microsoft-entra-id
  # for more details
  @list_blob_opts_base [max_results: Application.compile_env(:azurex, [Azurex.Blob.Config, :max_blobs_to_list], 5000)]
 
  def list(bucket, nil) do
    do_list(bucket, @list_blob_opts_base)
  end

  def list(bucket, prefix) do
    do_list(bucket, [{:prefix, prefix} | @list_blob_opts_base])
  end

  defp do_list(bucket, opts) do
    list_blobs = fn bucket, opts, marker ->
        opts = if marker, do: [{:marker, marker} | opts], else: opts
        {:ok, body} = Blob.list_blobs(bucket, opts)
        blob_names = ~x"//Blobs/Blob/Name/text()"sl
        marker = ~x"//NextMarker/text()"s
        {SweetXml.xpath(body, blob_names), SweetXml.xpath(body, marker)}
    end

    start_fun = fn -> 
      list_blobs.(bucket, opts, nil)
    end

    next_fun = fn 
      {[], :halt} -> {:halt, nil}
      {blobs, ""} -> 
        {blobs, {[], :halt}}  
      {blobs, marker} ->
        {blobs, list_blobs.(bucket, opts, marker)}
    end

    after_fun = &Function.identity/1
    Stream.resource(start_fun, next_fun, after_fun)
  end

  def get(bucket, key, opts) do
    case Blob.get_blob(key, bucket, opts) do
      {:ok, body} -> body
      {:error, _http_error} -> nil
    end
  end

  def put(bucket, key, blob, _opts) do
    Blob.put_blob(key, blob, nil, bucket)
  end

  def delete(bucket, key) do
    # returns :ok or {:error, :not_found}
    Blob.delete_blob(key, bucket)
  end

  def delete_many(bucket, keys) do
    # No idea how to load test this, azurite isn't
    # rated for high performance
    Enum.each(keys, &delete(bucket, &1))
  end
end

defmodule Hexpm.Store do
  @delete_batch 1000

  defp impl_bucket(atom) when is_atom(atom) do
    impl_bucket(Application.get_env(:hexpm, atom))
  end

  defp impl_bucket({impl, bucket}) when is_atom(impl) do
    {impl, bucket}
  end

  defp impl_bucket(bucket) when is_binary(bucket) do
    case String.split(bucket, ",", parts: 2) do
      ["local", bucket] -> {Hexpm.Store.Local, bucket}
      ["s3", bucket] -> {Hexpm.Store.S3, bucket}
      ["gcs", bucket] -> {Hexpm.Store.GCS, bucket}
    end
  end

  def list(bucket, prefix) do
    bucket
    |> list_objects(prefix)
    |> Stream.map(& &1.key)
  end

  @doc """
  The objects under `prefix` as `%{key: key, last_modified: datetime}`, for a
  caller that has to know how old an object is. `list/2` is the same listing
  with only the keys.
  """
  def list_objects(bucket, prefix) do
    {impl, bucket} = impl_bucket(bucket)
    impl.list_objects(bucket, prefix)
  end

  def get(bucket, key, opts \\ []) do
    {impl, bucket} = impl_bucket(bucket)
    impl.get(bucket, key, opts)
  end

  def size(bucket, key) do
    {impl, bucket} = impl_bucket(bucket)
    impl.size(bucket, key)
  end

  def stream(bucket, key) do
    {impl, bucket} = impl_bucket(bucket)
    impl.stream(bucket, key)
  end

  def fetch(bucket, key, opts \\ []) do
    {impl, bucket} = impl_bucket(bucket)

    try do
      case impl.get(bucket, key, opts) do
        nil -> :not_found
        body when is_binary(body) -> {:ok, body}
      end
    rescue
      exception -> {:error, {exception, __STACKTRACE__}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  def get_to_file(bucket, key, destination, opts \\ []) do
    {impl, bucket} = impl_bucket(bucket)
    impl.get_to_file(bucket, key, destination, opts)
  end

  def put(bucket, key, body, opts \\ []) do
    {impl, bucket} = impl_bucket(bucket)
    impl.put(bucket, key, body, opts)
  end

  def put_file(bucket, key, path, opts \\ []) do
    {impl, bucket} = impl_bucket(bucket)
    impl.put_file(bucket, key, path, opts)
  end

  def delete(bucket, key) do
    {impl, bucket} = impl_bucket(bucket)
    impl.delete(bucket, key)
  end

  def delete_many(bucket, keys) do
    {impl, bucket} = impl_bucket(bucket)
    impl.delete_many(bucket, keys)
  end

  @doc """
  Deletes every object under `prefix`. The listing is lazy and a prefix can
  cover a page per file of every version of a package, so the keys go out in
  batches rather than one call.
  """
  def delete_prefix(bucket, prefix) do
    bucket
    |> list(prefix)
    |> Stream.chunk_every(@delete_batch)
    |> Enum.each(&delete_many(bucket, &1))
  end
end

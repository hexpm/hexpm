defmodule Hexpm.Store do
  @type bucket :: String.t() | {module, String.t()}
  @type prefix :: key
  @type key :: String.t()
  @type body :: binary
  @type opts :: Keyword.t()

  @callback list(bucket, prefix) :: [key]
  @callback get(bucket, key, opts) :: body | nil
  @callback put(bucket, key, body, opts) :: term
  @callback delete(bucket, key) :: term
  @callback delete_many(bucket, [key]) :: :ok

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
    {impl, bucket} = impl_bucket(bucket)
    impl.list(bucket, prefix)
  end

  def get(bucket, key, opts) do
    {impl, bucket} = impl_bucket(bucket)
    impl.get(bucket, key, opts)
  end

  def put(bucket, key, body, opts) do
    {impl, bucket} = impl_bucket(bucket)
    impl.put(bucket, key, body, opts)
  end

  def delete(bucket, key) do
    {impl, bucket} = impl_bucket(bucket)
    impl.delete(bucket, key)
  end

  def delete_many(bucket, keys) do
    {impl, bucket} = impl_bucket(bucket)
    impl.delete_many(bucket, keys)
  end
end

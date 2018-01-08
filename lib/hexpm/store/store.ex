defmodule Hexpm.Store do
  @type region :: String.t()
  @type bucket :: String.t()
  @type prefix :: key
  @type key :: String.t()
  @type body :: binary
  @type opts :: Keyword.t()

  @callback list(region, bucket, prefix) :: [key]
  @callback get(region, bucket, key, opts) :: body
  @callback put(region, bucket, key, body, opts) :: term
  @callback delete(region, bucket, key) :: term
  @callback delete_many(region, bucket, [key]) :: [term]

  defp impl(), do: Application.get_env(:hexpm, :store_impl)

  def list(region, bucket, prefix), do: impl().list(region, bucket, prefix)
  def get(region, bucket, key, opts), do: impl().get(region, bucket, key, opts)
  def put(region, bucket, key, body, opts), do: impl().put(region, bucket, key, body, opts)
  def delete(region, bucket, key), do: impl().delete(region, bucket, key)
  def delete_many(region, bucket, keys), do: impl().delete_many(region, bucket, keys)
end

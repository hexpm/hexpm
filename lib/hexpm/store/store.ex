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

  @store_impl Application.get_env(:hexpm, :store_impl)

  defdelegate list(region, bucket, prefix), to: @store_impl
  defdelegate get(region, bucket, key, opts), to: @store_impl
  defdelegate put(region, bucket, key, body, opts), to: @store_impl
  defdelegate delete(region, bucket, key), to: @store_impl
  defdelegate delete_many(region, bucket, keys), to: @store_impl
end

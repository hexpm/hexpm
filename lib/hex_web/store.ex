defmodule HexWeb.Store do
  @type region  :: String.t
  @type bucket  :: String.t
  @type prefix  :: key
  @type key     :: String.t
  @type body    :: binary
  @type opts    :: Keyword.t

  @callback list(region, bucket, prefix) :: [key]
  @callback get(region, bucket, [key]) :: [body]
  @callback put(region, bucket, key, body, opts) :: term
  @callback delete(region, bucket, [key]) :: [term]

  @store_impl Application.get_env(:hex_web, :store_impl)

  def put(region, bucket, key, body, opts \\ [])

  defdelegate list(region, bucket, prefix),         to: @store_impl
  defdelegate get(region, bucket, key),             to: @store_impl
  defdelegate put(region, bucket, key, body, opts), to: @store_impl
  defdelegate delete(region, bucket, key),          to: @store_impl
end

defmodule HexWeb.Store do
  @type region  :: String.t
  @type bucket  :: String.t
  @type prefix  :: key
  @type key     :: String.t
  @type body    :: binary
  @type opts    :: Keyword.t
  @type wrap(t) :: t | [t]

  @callback list(region, bucket, prefix) :: [key]
  @callback get(region, bucket, wrap(key), opts) :: [body]
  @callback put(region, bucket, [{key, body, opts}], opts) :: term
  @callback put(region, bucket, key, body, opts) :: term
  @callback delete(region, bucket, wrap(key), opts) :: [term]

  @store_impl Application.get_env(:hex_web, :store_impl)

  def get(region, bucket, keys, opts \\ [])
  def delete(region, bucket, keys, opts \\ [])

  defdelegate list(region, bucket, prefix),         to: @store_impl
  defdelegate get(region, bucket, keys, opts),      to: @store_impl
  defdelegate put(region, bucket, objects, opts),   to: @store_impl
  defdelegate put(region, bucket, key, body, opts), to: @store_impl
  defdelegate delete(region, bucket, keys, opts),   to: @store_impl
end

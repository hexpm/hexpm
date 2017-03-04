defmodule HexWeb.Store do
  @type region  :: String.t
  @type bucket  :: String.t
  @type prefix  :: key
  @type key     :: String.t
  @type body    :: binary
  @type opts    :: Keyword.t

  @callback list(region, bucket, prefix) :: [key]
  @callback get(region, bucket, key, opts) :: body
  @callback get_many(region, bucket, [key], opts) :: [body]
  @callback get_each(region, bucket, [key], (key, body -> term), opts) :: term
  @callback get_reduce(region, bucket, [key], acc, (key, body, acc -> acc), opts) :: acc when acc: term
  @callback put(region, bucket, key, body, opts) :: term
  @callback put_many(region, bucket, [{key, body}], opts) :: term
  @callback put_multipart_init(region, bucket, key, opts) :: term
  @callback put_multipart_part(region, bucket, key, pos_integer, pos_integer, body) :: term
  @callback put_multipart_complete(region, bucket, key, pos_integer, [pos_integer]) :: term
  @callback delete(region, bucket, key, opts) :: term
  @callback delete_many(region, bucket, [key], opts) :: [term]

  @store_impl Application.get_env(:hex_web, :store_impl)

  defdelegate list(region, bucket, prefix),                                          to: @store_impl
  defdelegate get(region, bucket, key, opts),                                        to: @store_impl
  defdelegate get_many(region, bucket, keys, opts),                                  to: @store_impl
  defdelegate get_each(region, bucket, keys, fun, opts),                             to: @store_impl
  defdelegate get_reduce(region, bucket, keys, acc, fun, opts),                      to: @store_impl
  defdelegate put(region, bucket, key, body, opts),                                  to: @store_impl
  defdelegate put_many(region, bucket, objects, opts),                               to: @store_impl
  defdelegate put_multipart_init(region, bucket, key, opts),                         to: @store_impl
  defdelegate put_multipart_part(region, bucket, key, upload_id, part_number, body), to: @store_impl
  defdelegate put_multipart_complete(region, bucket, key, upload_id, parts),         to: @store_impl
  defdelegate delete(region, bucket, keys, opts),                                    to: @store_impl
  defdelegate delete_many(region, bucket, keys, opts),                               to: @store_impl
end

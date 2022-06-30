defmodule Hexpm.Store.Behaviour do
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
end

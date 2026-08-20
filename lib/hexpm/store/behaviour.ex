defmodule Hexpm.Store.Behaviour do
  @type bucket :: String.t() | {module, String.t()}
  @type prefix :: key
  @type key :: String.t()
  @type body :: binary
  @type opts :: Keyword.t()
  @typedoc """
  The written object's ETag: what S3 and GCS returned for the write, and
  for the local and memory stores a quoted MD5 of the body, the value S3
  gives a single-part upload.
  """
  @type etag :: String.t()

  @callback list(bucket, prefix) :: [key]
  @callback get(bucket, key, opts) :: body | nil
  @callback size(bucket, key) :: non_neg_integer() | nil
  @callback get_to_file(bucket, key, Path.t(), opts) :: :ok | nil
  @callback put(bucket, key, body, opts) :: {:ok, %{etag: etag}}
  @callback put_file(bucket, key, Path.t(), opts) :: {:ok, %{etag: etag}}
  @callback delete(bucket, key) :: term
  @callback delete_many(bucket, [key]) :: :ok
end

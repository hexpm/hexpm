defmodule Hexpm.Repository.Storage do
  @moduledoc """
  Low-level helpers shared by registry and policy builders for signing
  protobuf payloads, writing them to the repository bucket, and purging
  the matching Fastly surrogate keys.
  """

  @doc """
  Signs the given encoded protobuf payload with the configured private
  key and returns the gzipped result.
  """
  @spec sign_and_gzip(iodata()) :: binary()
  def sign_and_gzip(payload) do
    private_key = Application.fetch_env!(:hexpm, :private_key)

    payload
    |> :hex_registry.sign_protobuf(private_key)
    |> :zlib.gzip()
  end

  @doc """
  Writes `contents` to `key` in the repo bucket along with the standard
  surrogate-key/surrogate-control metadata and the supplied
  `cache_control` value.
  """
  @spec put_object(String.t(), iodata(), [String.t()], String.t()) :: term()
  def put_object(key, contents, surrogate_keys, cache_control) do
    meta = [
      {"surrogate-key", Enum.join(surrogate_keys, " ")},
      {"surrogate-control", "public, max-age=604800"}
    ]

    opts = [cache_control: cache_control, meta: meta]
    Hexpm.Store.put(:repo_bucket, key, contents, opts)
  end

  @doc """
  Deletes an object from the repo bucket.
  """
  @spec delete_object(String.t()) :: term()
  def delete_object(key) do
    Hexpm.Store.delete(:repo_bucket, key)
  end

  @doc """
  Purges the given surrogate keys on the hexrepo Fastly service.
  """
  @spec purge(String.t() | [String.t()]) :: term()
  def purge(surrogate_keys) do
    Hexpm.CDN.purge_key(:fastly_hexrepo, surrogate_keys)
  end
end

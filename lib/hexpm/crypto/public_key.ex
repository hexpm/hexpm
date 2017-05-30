defmodule Hexpm.Crypto.PublicKey do
  @doc """
  Decodes a public key and raises if the key is invalid.
  """
  def decode!(id, key) do
    [rsa_public_key] = :public_key.pem_decode(key)
    :public_key.pem_entry_decode(rsa_public_key)
  rescue
    _ ->
      Mix.raise """
      Could not decode public key for #{id}. The public key contents are shown below.

      #{key}

      Public keys must be valid and be in the PEM format.
      """
  end

  @doc """
  Verifies the given binary has the proper signature using the system public keys.
  """
  def verify(binary, hash, signature, keys, id) do
    Enum.any?(keys, fn key ->
      :public_key.verify(binary, hash, signature, decode!(id, key))
    end)
  end
end

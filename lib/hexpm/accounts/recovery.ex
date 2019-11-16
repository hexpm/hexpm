defmodule Hexpm.Accounts.Recovery do
  @moduledoc """
  Functions used for generating and verifying recovery codes.

  ### Examples:
  iex(1)> codes = [code|_more_codes] = Hexpm.Accounts.Recovery.gen_recovery_codes
  iex(2)> _hashes = [hash|_more_hashes] = Hexpm.Accounts.Recovery.hash_recovery_codes(codes)
  iex(3)> true = Hexpm.Accounts.Recovery.verify_code(code, hash)
  true
  iex(4)> true = Hexpm.Accounts.Recovery.verify_code(String.split(code, "-"), hash)
  true
  iex(5)> false = Hexpm.Accounts.Recovery.verify_code("foo", hash)
  false
  iex(6)> false = Hexpm.Accounts.Recovery.verify_code(code, "bad_hash")
  false
  """

  @rand_bytes 10
  @part_size 4

  def gen_recovery_codes, do: Enum.map(1..5, fn _ -> gen_code() end)

  def hash_recovery_codes(codes), do: Enum.map(codes, &hash_code/1)

  def verify_code(<<code::binary-size(19)>>, hash) do
    code
    |> String.split("-")
    |> do_verify_code(hash)
  end

  defp do_verify_code([_p1, _p2, _p3, _p4] = parts, hash) do
    parts
    |> Enum.join("-")
    |> Bcrypt.verify_pass(hash)
  end

  defp do_verify_code(_, _), do: false

  def hash_code(code), do: Bcrypt.hash_pwd_salt(code)

  def gen_code do
    :crypto.strong_rand_bytes(@rand_bytes)
    |> Base.hex_encode32(case: :lower)
    |> String.to_charlist()
    |> Enum.chunk_every(@part_size)
    |> Enum.intersperse("-")
    |> List.to_string()
  end
end

defmodule Hexpm.Accounts.BackupCode do
  @doc """
  Generate `n` backup codes.
  """
  def generate(n) do
    for _x <- 1..n, do: _generate()
  end

  @doc """
  Check if a given string matches the format of a backup code.
  Prevents unnecessary decryption.
  """
  def is?(code) do
    Regex.match?(~r/....-....-....-..../, code)
  end

  @doc """
  Checks if a list (`encrypted`) of encrypted backup codes contains
  the given code (`code`).

  Expensive operation (can be ~400ms!)
  """
  def included?(encrypted, code) do
    decrypt(encrypted)
    |> Enum.member?(code)
  end

  def encrypt(codes) when is_list(codes), do: Enum.map(codes, &encrypt/1)
  def encrypt(backupcode) do
    app_secret = Application.get_env(:hexpm, :totp_encryption_secret)
    enc_tag = "HEXTOTPBACKUP"

    Hexpm.Crypto.encrypt(app_secret, backupcode, enc_tag)
  end

  def decrypt(codes) when is_list(codes), do: Enum.map(codes, &decrypt/1)
  def decrypt(encrypted) do
    app_secret = Application.get_env(:hexpm, :totp_encryption_secret)
    enc_tag = "HEXTOTPBACKUP"

    {:ok, decrypted} = Hexpm.Crypto.decrypt(app_secret, encrypted, enc_tag)
    decrypted
  end

  defp _generate() do
    code =
      :crypto.strong_rand_bytes(10)
      |> Base.encode32(case: :lower)

    Regex.scan(~r/..../, code)
    |> List.flatten
    |> Enum.join("-") # "xxxx-xxxx-xxxx-xxxx"
  end
end

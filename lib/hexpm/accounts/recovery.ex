defmodule Hexpm.Accounts.Recovery do
  @moduledoc """
  Functions used for generating and verifying recovery codes.

  ### Examples:
  iex(1)> alias Hexpm.Accounts.{Recovery, RecoveryCode}
  [Hexpm.Accounts.Recovery, Hexpm.Accounts.RecoveryCode]
  iex(2)> codes = [%RecoveryCode{code: code_str} = code | _rest] = Recovery.gen_code_set
  iex(3)> {:ok, ^code} = Hexpm.Accounts.Recovery.verify(codes, code_str)
  iex(4)> {:error, :invalid_code} = Hexpm.Accounts.Recovery.verify(codes, "bad-code")
  {:error, :invalid_code}
  """

  alias Hexpm.Accounts.RecoveryCode

  @rand_bytes 10
  @part_size 4

  @typep recovery_code() :: <<_::152>>

  @spec gen_code_set() :: [%RecoveryCode{}]
  def gen_code_set, do: Enum.map(1..5, fn _ -> %RecoveryCode{code: gen_code()} end)

  @spec gen_code() :: recovery_code()
  def gen_code do
    :crypto.strong_rand_bytes(@rand_bytes)
    |> Base.hex_encode32(case: :lower)
    |> String.to_charlist()
    |> Enum.chunk_every(@part_size)
    |> Enum.intersperse("-")
    |> List.to_string()
  end

  @spec verify([RecoveryCode.t()], recovery_code()) ::
          {:ok, RecoveryCode.t()} | {:error, :invalid_code}
  def verify(recovery_codes, <<code_str::binary-size(19)>>) do
    case find_valid_code(recovery_codes, code_str) do
      %RecoveryCode{code: ^code_str} = code -> {:ok, code}
      _otherwise -> {:error, :invalid_code}
    end
  end

  def verify(_recovery_codes, _invalid_code), do: {:error, :invalid_code}

  defp find_valid_code(recovery_codes, code_str) do
    Enum.find(recovery_codes, fn rc -> is_nil(rc.used_at) and code_str == rc.code end)
  end
end

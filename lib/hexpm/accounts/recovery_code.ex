defmodule Hexpm.Accounts.RecoveryCode do
  use Hexpm.Schema

  alias Hexpm.Accounts.RecoveryCode

  @derive {Jason.Encoder, only: []}

  @rand_bytes 10
  @part_size 4
  @typep recovery_code() :: <<_::152>>

  @primary_key false
  embedded_schema do
    field :code, :string
    field :used_at, :utc_datetime_usec
  end

  def changeset(recovery_code, params) do
    cast(recovery_code, params, [:code, :used_at])
  end

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

  @spec verify([recovery_code()], recovery_code()) ::
          {:ok, recovery_code()} | {:error, :invalid_code}
  def verify(recovery_codes, code_str) do
    case find_valid_code(recovery_codes, code_str) do
      %RecoveryCode{code: ^code_str} = code -> {:ok, code}
      _otherwise -> {:error, :invalid_code}
    end
  end

  defp find_valid_code(recovery_codes, code_str) do
    Enum.find(recovery_codes, fn rc -> is_nil(rc.used_at) and code_str == rc.code end)
  end
end

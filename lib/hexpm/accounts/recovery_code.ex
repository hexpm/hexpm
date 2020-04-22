defmodule Hexpm.Accounts.RecoveryCode do
  use Hexpm.Schema

  alias Hexpm.Accounts.RecoveryCode

  @derive {Jason.Encoder, only: []}

  @rand_bytes 10
  @part_size 4

  embedded_schema do
    field :code, :string
    field :used_at, :utc_datetime_usec
  end

  def changeset(recovery_code, params) do
    cast(recovery_code, params, [:code, :used_at])
  end

  def generate_set() do
    Enum.map(1..10, fn _ -> %RecoveryCode{code: generate()} end)
  end

  def generate() do
    :crypto.strong_rand_bytes(@rand_bytes)
    |> Base.hex_encode32(case: :lower)
    |> String.to_charlist()
    |> Enum.chunk_every(@part_size)
    |> Enum.intersperse("-")
    |> List.to_string()
  end

  def verify(recovery_codes, code_str) do
    case find_valid_code(recovery_codes, code_str) do
      %RecoveryCode{code: ^code_str} = code -> {:ok, code}
      nil -> {:error, :invalid_code}
    end
  end

  defp find_valid_code(recovery_codes, code_str) do
    Enum.find(recovery_codes, fn rc ->
      is_nil(rc.used_at) and Plug.Crypto.secure_compare(code_str, rc.code)
    end)
  end
end

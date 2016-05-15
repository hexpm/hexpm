defmodule HexWeb.Version do
  @behaviour Ecto.Type

  defstruct [:major, :minor, :patch, :pre, :build]

  def type, do: :string

  def blank?(""),  do: true
  def blank?(nil), do: true
  def blank?(_),   do: false

  def cast(%Version{} = version),
    do: {:ok, version}
  def cast(string) when is_binary(string),
    do: Version.parse(string)
  def cast(_),
    do: :error

  def load(string),
    do: Version.parse(string)

  def dump(%Version{} = version),
    do: {:ok, to_string(version)}
  def dump(version) when is_binary(version),
    do: {:ok, version}
end

defimpl Poison.Encoder, for: Version do
  def encode(version, _),
    do: "\"" <> to_string(version) <> "\""
end

defimpl Ecto.DataType, for: Version do
  def dump(version),
    do: cast(version, HexWeb.Version)

  def cast(version, HexWeb.Version),
    do: {:ok, struct(HexWeb.Version, version)}
  def cast(_, _),
    do: :error
end

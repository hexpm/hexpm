defmodule Hexpm.Version do
  @behaviour Ecto.Type

  def type(), do: :string

  def cast(%Version{} = version), do: {:ok, version}
  def cast(string) when is_binary(string), do: Version.parse(string)
  def cast(_), do: :error

  def load(string), do: Version.parse(string)

  def dump(%Version{} = version), do: {:ok, to_string(version)}
  def dump(version) when is_binary(version), do: {:ok, version}
end

defimpl Poison.Encoder, for: Version do
  def encode(version, _), do: ~s("#{version}")
end

defimpl Ecto.DataType, for: Version do
  def dump(version), do: cast(version, Hexpm.Version)

  def cast(version, Hexpm.Version), do: {:ok, struct(Hexpm.Version, version)}
  def cast(_, _), do: :error
end

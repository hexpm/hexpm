defmodule Hexpm.Version do
  @behaviour Ecto.Type

  def type(), do: :string

  def cast(%Version{} = version), do: {:ok, version}

  def cast(string) when is_binary(string) do
    case Version.parse(string) do
      {:ok, _} = ok ->
        ok

      :error ->
        {:error, message: "is invalid SemVer"}
    end
  end

  def cast(_), do: {:error, message: "is invalid SemVer"}

  def load(string), do: Version.parse(string)

  def dump(%Version{} = version), do: {:ok, to_string(version)}
  def dump(version) when is_binary(version), do: {:ok, version}

  def embed_as(_format), do: :self

  def equal?(nil, nil), do: true
  def equal?(nil, _right), do: false
  def equal?(_left, nil), do: false
  def equal?(left, right), do: Version.compare(left, right) == :eq
end

defimpl Jason.Encoder, for: Version do
  def encode(version, _), do: ~s("#{version}")
end

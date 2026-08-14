defmodule Hexpm.Version do
  @behaviour Ecto.Type

  @numeric_identifier 1
  @alphanumeric_identifier 2
  @max_numeric_component 9_223_372_036_854_775_807
  @max_prerelease_length 64

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

  def validate(%Version{build: nil} = version) do
    numeric_components =
      [version.major, version.minor, version.patch] ++ numeric_identifiers(version)

    cond do
      Enum.any?(numeric_components, &(&1 > @max_numeric_component)) ->
        {:error, "numeric components must be at most #{@max_numeric_component}"}

      prerelease_length(version.pre) > @max_prerelease_length ->
        {:error, "prerelease must be at most #{@max_prerelease_length} characters"}

      true ->
        :ok
    end
  end

  def validate(%Version{}), do: {:error, "build number not allowed"}

  def sort_key(%Version{} = version) do
    [
      encode_number(version.major),
      encode_number(version.minor),
      encode_number(version.patch),
      encode_pre(version.pre)
    ]
    |> IO.iodata_to_binary()
  end

  defp encode_pre([]), do: <<1>>

  defp encode_pre(identifiers) do
    [<<0>>, Enum.map(identifiers, &encode_identifier/1), <<0>>]
  end

  defp encode_identifier(identifier) when is_integer(identifier) do
    [<<@numeric_identifier>>, encode_number(identifier), <<0>>]
  end

  defp encode_identifier(identifier) when is_binary(identifier) do
    [<<@alphanumeric_identifier>>, identifier, <<0>>]
  end

  defp encode_number(number), do: <<number::unsigned-big-64>>

  defp numeric_identifiers(version) do
    Enum.filter(version.pre, &is_integer/1)
  end

  defp prerelease_length(identifiers) do
    identifiers
    |> Enum.map_join(".", &to_string/1)
    |> byte_size()
  end
end

defimpl JSON.Encoder, for: Version do
  def encode(version, encoder), do: encoder.(to_string(version), encoder)
end

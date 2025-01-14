defmodule Hexpm.VersionRequirement do
  use Ecto.Type

  def type(), do: :string

  def cast(%Version.Requirement{} = version_requirement), do: {:ok, version_requirement}

  def cast(string) when is_binary(string) do
    case Version.parse_requirement(string) do
      {:ok, _} = ok ->
        ok

      :error ->
        {:error, message: "is invalid Version Requirement"}
    end
  end

  def cast(_), do: {:error, message: "is invalid Version Requirement"}

  def load(string), do: Version.parse_requirement(string)

  def dump(%Version.Requirement{} = version_requirement),
    do: {:ok, to_string(version_requirement)}

  def dump(version_requirement) when is_binary(version_requirement),
    do: {:ok, version_requirement}

  def embed_as(_format), do: :self
end

defimpl Jason.Encoder, for: Version.Requirement do
  def encode(version_requirement, _), do: ~s("#{version_requirement}")
end

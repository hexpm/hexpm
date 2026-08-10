defmodule Hexpm.SecretScan.Finding do
  @moduledoc """
  One credential found in one release.

  `fingerprint` is an HMAC of the matched value and `preview` is masked; the
  credential itself is never stored. `tarball_checksum` records the content the
  finding was seen in, since a release can be overwritten in its grace window.
  """

  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "secret_findings" do
    field :tarball_checksum, :binary
    field :rule, :string
    field :file_path, :string
    field :line, :integer
    field :byte_offset, :integer
    field :fingerprint, :binary
    field :preview, :string

    belongs_to :release, Release
    belongs_to :package, Package

    timestamps(updated_at: false)
  end

  @fields ~w(release_id package_id tarball_checksum rule file_path line byte_offset fingerprint preview)a

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> unique_constraint([:release_id, :fingerprint, :file_path])
  end

  @max_path 120

  @doc """
  Where the finding is, for display.

  The path comes from a tar entry name the publisher chose, and this ends up in
  a plain text email to the package owners. A name may contain newlines, so
  without collapsing them an attacker gets to write their own paragraph into
  mail that arrives from hex.pm — and anyone can be added as an owner of a
  package without consenting to it.
  """
  def location(%__MODULE__{} = finding), do: location(Map.from_struct(finding))

  def location(%{file_path: path, line: line}) when is_integer(line) and line > 0 do
    "#{display_path(path)}:#{line}"
  end

  def location(%{file_path: path, byte_offset: offset}), do: "#{display_path(path)}@#{offset}"

  defp display_path(path) do
    path
    |> String.replace_invalid()
    |> String.replace(~r/[[:cntrl:]]/u, "�")
    |> String.slice(0, @max_path)
  end
end

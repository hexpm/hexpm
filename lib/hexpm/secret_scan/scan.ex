defmodule Hexpm.SecretScan.Scan do
  use Hexpm.Schema

  @type t :: %__MODULE__{}

  schema "secret_scans" do
    field :tarball_checksum, :binary
    field :finding_count, :integer, default: 0
    field :truncated, :boolean, default: false
    field :notified_at, :utc_datetime_usec

    belongs_to :release, Release

    timestamps()
  end

  def changeset(scan, attrs) do
    scan
    |> cast(attrs, [:release_id, :tarball_checksum, :finding_count, :truncated, :notified_at])
    |> validate_required([:release_id, :tarball_checksum])
    |> unique_constraint(:release_id)
  end
end

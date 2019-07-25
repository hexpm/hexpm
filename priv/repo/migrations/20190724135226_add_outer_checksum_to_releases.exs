defmodule Hexpm.RepoBase.Migrations.AddOuterChecksumToReleases do
  use Ecto.Migration

  def change do
    alter table(:releases) do
      add(:inner_checksum, :binary)
      add(:outer_checksum, :binary)
    end

    execute """
    UPDATE releases SET inner_checksum = decode(checksum, 'hex')
    """

    alter table(:releases) do
      remove(:checksum)
    end
  end
end

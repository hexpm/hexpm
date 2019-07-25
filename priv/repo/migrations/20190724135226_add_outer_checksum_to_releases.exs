defmodule Hexpm.RepoBase.Migrations.AddOuterChecksumToReleases do
  use Ecto.Migration

  def change do
    rename(table(:releases), :checksum, to: :inner_checksum)

    alter table(:releases) do
      add(:outer_checksum, :string)
    end
  end
end

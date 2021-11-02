defmodule Hexpm.RepoBase.Migrations.AddTrialEndToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add(:trial_end, :utc_datetime_usec, default: "NOW()")
    end

    alter table(:organizations) do
      modify(:trial_end, :utc_datetime_usec, default: nil, null: false)
    end
  end
end

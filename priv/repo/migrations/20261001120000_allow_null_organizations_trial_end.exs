defmodule Hexpm.Repo.Migrations.AllowNullOrganizationsTrialEnd do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      modify :trial_end, :utc_datetime_usec,
        null: true,
        from: {:utc_datetime_usec, null: false}
    end
  end
end

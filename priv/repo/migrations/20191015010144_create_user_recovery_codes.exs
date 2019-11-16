defmodule Hexpm.RepoBase.Migrations.CreateUserRecoveryCodes do
  use Ecto.Migration

  def change do
    create table("user_recovery_codes") do
      add :user_id, references(:users), null: false
      add :code_digest, :string, null: false
      add :used_at, :utc_datetime_usec
      timestamps()
    end

    create unique_index(:user_recovery_codes, [:code_digest])
  end
end

defmodule Hexpm.RepoBase.Migrations.CreateRateLimits do
  use Ecto.Migration

  def change do
    create table(:rate_limits, primary_key: false) do
      add :key, :text, primary_key: true
      add :count, :integer, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create index(:rate_limits, [:expires_at])
  end
end

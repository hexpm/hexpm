defmodule Hexpm.RepoBase.Migrations.AddSsoSeatExpansionFailedAt do
  use Ecto.Migration

  def up() do
    execute("SET lock_timeout TO '5s'")

    alter table(:organization_sso_connections) do
      add :seat_expansion_failed_at, :utc_datetime_usec
    end

    execute("SET lock_timeout TO DEFAULT")
  end

  def down() do
    execute("SET lock_timeout TO '5s'")

    alter table(:organization_sso_connections) do
      remove :seat_expansion_failed_at
    end

    execute("SET lock_timeout TO DEFAULT")
  end
end

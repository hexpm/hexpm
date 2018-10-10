defmodule Hexpm.RepoBase.Migrations.UpdateTimestampFields do
  use Ecto.Migration

  defp fixup(table, columns) do
    alter table(table) do
      for column <- columns do
        modify(column, :utc_datetime_usec)
      end
    end
  end

  def change do
    fixup(:emails, [:verification_expiry])

    fixup(:packages, [:docs_updated_at])

    fixup(:organization_users, [:inserted_at, :updated_at])

    fixup(:organizations, [:inserted_at, :updated_at])

    fixup(:password_resets, [:inserted_at])

    fixup(:sessions, [:inserted_at, :updated_at])
  end
end

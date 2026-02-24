defmodule Hexpm.Repo.Migrations.AddOptionalEmailsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :optional_emails, :map
    end
  end
end

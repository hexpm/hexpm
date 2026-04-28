defmodule Hexpm.Repo.Migrations.AddOptionalEmailsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists :optional_emails, :map
    end
  end
end

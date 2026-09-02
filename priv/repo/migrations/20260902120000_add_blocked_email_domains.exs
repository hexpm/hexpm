defmodule Hexpm.Repo.Migrations.AddBlockedEmailDomains do
  use Ecto.Migration

  def change do
    create table(:blocked_email_domains) do
      add :domain, :string, null: false
      add :comment, :string
      timestamps(updated_at: false)
    end

    create unique_index(:blocked_email_domains, [:domain])
  end
end

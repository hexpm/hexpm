defmodule Hexpm.RepoBase.Migrations.CreateGithubAccounts do
  use Ecto.Migration

  def change do
    create table(:github_accounts) do
      add(:github_user_id, :integer)
      add(:user_id, references(:users))
    end

    create(index(:github_accounts, [:user_id]))
    create(unique_index(:github_accounts, [:github_user_id]))
  end
end

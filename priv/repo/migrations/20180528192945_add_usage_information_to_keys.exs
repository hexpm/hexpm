defmodule Hexpm.Repo.Migrations.AddUsageInformationToKeys do
  use Ecto.Migration

  def change do
    alter table(:keys) do
      add(:last_used_at, :timestamp)
      add(:last_user_agent, :string)
      add(:last_ip, :string)
    end
  end
end

defmodule Hexpm.Repo.Migrations.AddVerificationExpiryToEmails do
  use Ecto.Migration

  def change do
    alter table(:emails) do
      add(:verification_expiry, :naive_datetime)
    end
  end
end

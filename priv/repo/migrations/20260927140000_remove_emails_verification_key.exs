defmodule Hexpm.Repo.Migrations.RemoveEmailsVerificationKey do
  use Ecto.Migration

  def change do
    alter table(:emails) do
      remove :verification_key, :string
    end
  end
end

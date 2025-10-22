defmodule Hexpm.RepoBase.Migrations.AddSeatsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :billing_seats, :integer
    end
  end
end

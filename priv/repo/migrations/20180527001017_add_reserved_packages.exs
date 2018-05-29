defmodule Hexpm.Repo.Migrations.AddReservedPackages do
  use Ecto.Migration

  def change do
    create table(:reserved_packages) do
      add(
        :repository_id,
        references(:repositories, on_delete: :delete_all, on_update: :update_all),
        null: false
      )

      add(:name, :string, null: false)
      add(:version, :string)
      add(:reason, :string)
    end

    create(unique_index(:reserved_packages, [:repository_id, :name, :version]))
  end
end

defmodule Hexpm.Repo.Migrations.CreateTrustedPublishers do
  use Ecto.Migration

  def change do
    create table(:trusted_publishers) do
      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :issuer, :string, null: false
      add :repository_owner, :string, null: false
      add :repository_owner_id, :string, null: false
      add :repository_id, :string, null: false
      add :repository, :string, null: false
      add :workflow, :string, null: false
      add :environment, :string, null: false, default: ""

      timestamps()
    end

    create index(:trusted_publishers, [:package_id])
    create index(:trusted_publishers, [:provider, :repository, :workflow])

    create unique_index(
             :trusted_publishers,
             [:package_id, :provider, :repository, :workflow, :environment],
             name: :trusted_publishers_package_config_unique
           )
  end
end

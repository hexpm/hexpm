defmodule Hexpm.Repo.Migrations.AddTrustedPublisherToReleases do
  use Ecto.Migration

  def change do
    alter table(:releases) do
      add :trusted_publisher_id, references(:trusted_publishers, on_delete: :nilify_all)
      add :oidc_claims, :map
    end

    create index(:releases, [:trusted_publisher_id])
  end
end

defmodule Hexpm.RepoBase.Migrations.SetDownloadsPackageIdNotNull do
  use Ecto.Migration

  def change do
    alter table(:downloads) do
      modify(
        :package_id,
        references(:packages, on_delete: :delete_all),
        from: references(:packages, on_delete: :delete_all),
        null: false
      )
    end
  end
end

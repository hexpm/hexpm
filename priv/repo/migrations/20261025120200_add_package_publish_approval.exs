defmodule Hexpm.Repo.Migrations.AddPackagePublishApproval do
  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:packages) do
      add :require_publish_approval, :boolean, default: false, null: false
    end

    alter table(:packages) do
      modify :require_publish_approval, :boolean, default: true, null: false
    end
  end

  def down do
    execute("SET LOCAL lock_timeout TO '5s'")

    alter table(:packages) do
      remove :require_publish_approval
    end
  end
end

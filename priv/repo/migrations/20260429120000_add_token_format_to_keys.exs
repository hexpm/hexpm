defmodule Hexpm.Repo.Migrations.AddTokenFormatToKeys do
  use Ecto.Migration

  def change do
    alter table(:keys) do
      add :token_format, :string, null: false, default: "v1"
    end
  end
end

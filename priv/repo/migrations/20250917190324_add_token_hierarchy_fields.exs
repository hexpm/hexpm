defmodule Hexpm.RepoBase.Migrations.AddTokenHierarchyFields do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :parent_token_id, references(:oauth_tokens, on_delete: :nothing)
      add :token_family_id, :string
    end

    create index(:oauth_tokens, [:parent_token_id])
    create index(:oauth_tokens, [:token_family_id])
  end
end

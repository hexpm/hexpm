defmodule Hexpm.Repo.Migrations.AddTwofactorToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :twofactor, :jsonb, default: fragment("json_build_object('id', uuid_generate_v4()::text, 'enabled', false, 'type', 'disabled', 'secret', '', 'backupcodes', '[]'::json)::jsonb")
    end
  end
end



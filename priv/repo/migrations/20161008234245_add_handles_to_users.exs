defmodule Hexpm.Repo.Migrations.AddHandlesToUsers do
  use Ecto.Migration

  def change() do
    alter table(:users) do
      add(
        :handles,
        :jsonb,
        default: fragment("json_build_object('id', uuid_generate_v4()::text)::jsonb")
      )
    end
  end
end

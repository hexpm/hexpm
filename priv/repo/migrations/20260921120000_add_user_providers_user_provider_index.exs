defmodule Hexpm.RepoBase.Migrations.AddUserProvidersUserProviderIndex do
  use Ecto.Migration

  def up do
    # The index takes SHARE on a table read on the GitHub login path. Give up
    # rather than queue behind a long-running read and hold every writer
    # behind us.
    execute("SET lock_timeout TO '5s'")

    execute("""
    DELETE FROM user_providers a
    USING user_providers b
    WHERE a.user_id = b.user_id
      AND a.provider = b.provider
      AND a.id > b.id
    """)

    create unique_index(:user_providers, [:user_id, :provider])

    execute("SET lock_timeout TO DEFAULT")
  end

  def down do
    drop_if_exists unique_index(:user_providers, [:user_id, :provider])
  end
end

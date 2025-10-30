defmodule Hexpm.Repo.Migrations.CreateUserSessions do
  use Ecto.Migration

  def up do
    # Create unified user_sessions table
    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :name, :string
      add :revoked_at, :utc_datetime_usec
      add :last_use, :jsonb

      # Browser-specific fields
      add :session_token, :binary

      # OAuth-specific fields
      add :client_id, references(:oauth_clients, column: :client_id, type: :uuid, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:user_sessions, [:user_id])
    create index(:user_sessions, [:type])
    create index(:user_sessions, [:session_token])
    create index(:user_sessions, [:client_id])

    # Migrate browser sessions from sessions table
    execute """
    INSERT INTO user_sessions (user_id, type, name, session_token, inserted_at, updated_at)
    SELECT
      (data->>'user_id')::integer,
      'browser',
      'Browser Session',
      token,
      inserted_at,
      updated_at
    FROM sessions
    WHERE data->>'user_id' IS NOT NULL
    """

    # Migrate OAuth sessions from oauth_sessions table
    execute """
    INSERT INTO user_sessions (user_id, type, name, revoked_at, last_use, client_id, inserted_at, updated_at)
    SELECT
      user_id,
      'oauth',
      name,
      revoked_at,
      jsonb_build_object(
        'used_at', last_use->>'used_at',
        'ip', last_use->>'ip',
        'user_agent', last_use->>'user_agent'
      ),
      client_id,
      inserted_at,
      updated_at
    FROM oauth_sessions
    """

    # Create temporary mapping table for oauth_tokens update
    execute """
    CREATE TEMP TABLE session_id_mapping AS
    SELECT
      os.id as old_session_id,
      us.id as new_user_session_id
    FROM oauth_sessions os
    JOIN user_sessions us ON
      us.user_id = os.user_id AND
      us.client_id = os.client_id AND
      us.type = 'oauth' AND
      us.inserted_at = os.inserted_at
    """

    # Add new column to oauth_tokens
    alter table(:oauth_tokens) do
      add :user_session_id, references(:user_sessions, on_delete: :nilify_all)
    end

    # Update oauth_tokens to reference user_sessions
    execute """
    UPDATE oauth_tokens ot
    SET user_session_id = sm.new_user_session_id
    FROM session_id_mapping sm
    WHERE ot.session_id = sm.old_session_id
    """

    # Drop old session_id column from oauth_tokens
    alter table(:oauth_tokens) do
      remove :session_id
    end

    # Drop oauth_sessions table
    drop table(:oauth_sessions)

    # Clean up sessions table - remove user sessions, keep only Plug session storage
    execute "DELETE FROM sessions WHERE data->>'user_id' IS NOT NULL"
  end

  def down do
    # Recreate oauth_sessions table
    create table(:oauth_sessions) do
      add :name, :string
      add :revoked_at, :utc_datetime_usec
      add :last_use, :jsonb
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :client_id, references(:oauth_clients, column: :client_id, type: :uuid, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:oauth_sessions, [:user_id])
    create index(:oauth_sessions, [:client_id])

    # Migrate OAuth sessions back
    execute """
    INSERT INTO oauth_sessions (user_id, name, revoked_at, last_use, client_id, inserted_at, updated_at)
    SELECT
      user_id,
      name,
      revoked_at,
      last_use,
      client_id,
      inserted_at,
      updated_at
    FROM user_sessions
    WHERE type = 'oauth'
    """

    # Migrate browser sessions back to sessions table
    execute """
    INSERT INTO sessions (token, data, inserted_at, updated_at)
    SELECT
      session_token,
      jsonb_build_object('user_id', user_id::text),
      inserted_at,
      updated_at
    FROM user_sessions
    WHERE type = 'browser'
    """

    # Restore session_id column
    alter table(:oauth_tokens) do
      add :session_id, references(:oauth_sessions, on_delete: :nilify_all)
    end

    # Update oauth_tokens back
    execute """
    UPDATE oauth_tokens ot
    SET session_id = os.id
    FROM oauth_sessions os
    JOIN user_sessions us ON
      us.user_id = os.user_id AND
      us.client_id = os.client_id AND
      us.type = 'oauth'
    WHERE ot.user_session_id = us.id
    """

    # Remove user_session_id column
    alter table(:oauth_tokens) do
      remove :user_session_id
    end

    # Drop user_sessions table
    drop table(:user_sessions)
  end
end

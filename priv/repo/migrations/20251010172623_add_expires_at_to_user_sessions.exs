defmodule Hexpm.Repo.Migrations.AddExpiresAtToUserSessions do
  use Ecto.Migration

  def up do
    # Add expires_at column
    alter table(:user_sessions) do
      add :expires_at, :utc_datetime_usec
    end

    # Backfill OAuth sessions: use the earliest refresh_token_expires_at from their tokens
    execute """
    UPDATE user_sessions us
    SET expires_at = (
      SELECT MIN(ot.refresh_token_expires_at)
      FROM oauth_tokens ot
      WHERE ot.user_session_id = us.id
        AND ot.refresh_token_expires_at IS NOT NULL
    )
    WHERE us.type = 'oauth'
      AND EXISTS (
        SELECT 1 FROM oauth_tokens ot2
        WHERE ot2.user_session_id = us.id
          AND ot2.refresh_token_expires_at IS NOT NULL
      )
    """

    # Backfill browser sessions: inserted_at + 30 days
    execute """
    UPDATE user_sessions
    SET expires_at = inserted_at + INTERVAL '30 days'
    WHERE type = 'browser'
      AND expires_at IS NULL
    """

    # Add index for cleanup queries
    create index(:user_sessions, [:expires_at])
  end

  def down do
    drop index(:user_sessions, [:expires_at])

    alter table(:user_sessions) do
      remove :expires_at
    end
  end
end

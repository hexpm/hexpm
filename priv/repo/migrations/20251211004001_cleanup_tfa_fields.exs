defmodule Hexpm.RepoBase.Migrations.CleanupTfaFields do
  use Ecto.Migration

  def up do
    # Only keep tfa if it was fully enabled in the old model
    execute """
    UPDATE users
    SET tfa = CASE
      WHEN tfa IS NOT NULL
           AND (tfa->>'tfa_enabled')::boolean = true
           AND (tfa->>'app_enabled')::boolean = true
           AND (tfa->>'secret') IS NOT NULL THEN
        tfa - 'tfa_enabled' - 'app_enabled'
      ELSE
        NULL
    END
    WHERE tfa IS NOT NULL
    """
  end

  def down do
    execute """
    UPDATE users
    SET tfa = tfa || '{"tfa_enabled": true, "app_enabled": true}'::jsonb
    WHERE tfa IS NOT NULL AND (tfa->>'secret') IS NOT NULL
    """
  end
end

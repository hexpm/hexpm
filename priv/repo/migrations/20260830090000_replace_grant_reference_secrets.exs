defmodule Hexpm.RepoBase.Migrations.ReplaceGrantReferenceSecrets do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE oauth_tokens t
    SET grant_reference = 'device_code:' || d.id
    FROM device_codes d
    WHERE t.grant_type = 'urn:ietf:params:oauth:grant-type:device_code'
      AND t.grant_reference = d.device_code
    """)

    execute("""
    UPDATE oauth_tokens
    SET grant_reference = NULL
    WHERE grant_reference IS NOT NULL
      AND grant_reference !~ '^(key|token|authorization_code|device_code):'
    """)
  end

  def down do
  end
end

defmodule Hexpm.Repo.Migrations.SeedTrustedPublisherOauthClient do
  use Ecto.Migration

  @client_id "a1111111-1111-4111-8111-111111111111"

  def up do
    execute("""
    INSERT INTO oauth_clients (
      client_id, name, client_type, allowed_grant_types, allowed_scopes,
      redirect_uris, inserted_at, updated_at
    ) VALUES (
      '#{@client_id}',
      'Trusted Publisher',
      'public',
      ARRAY['trusted_publisher'],
      ARRAY['package'],
      ARRAY[]::text[],
      NOW(),
      NOW()
    )
    ON CONFLICT (client_id) DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM oauth_clients WHERE client_id = '#{@client_id}'")
  end
end

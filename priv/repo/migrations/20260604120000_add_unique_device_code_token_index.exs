defmodule Hexpm.RepoBase.Migrations.AddUniqueDeviceCodeTokenIndex do
  use Ecto.Migration

  @grant_type "urn:ietf:params:oauth:grant-type:device_code"
  @index_name :oauth_tokens_device_code_grant_reference_client_id_index

  def up do
    execute("""
    UPDATE oauth_tokens
    SET revoked_at = now()
    WHERE id IN (
      SELECT id
      FROM (
        SELECT id,
               row_number() OVER (
                 PARTITION BY grant_reference, client_id
                 ORDER BY inserted_at DESC, id DESC
               ) AS rn
        FROM oauth_tokens
        WHERE grant_type = '#{@grant_type}' AND revoked_at IS NULL
      ) ranked
      WHERE ranked.rn > 1
    )
    """)

    create unique_index(:oauth_tokens, [:grant_reference, :client_id],
             where: "grant_type = '#{@grant_type}' AND revoked_at IS NULL",
             name: @index_name
           )
  end

  def down do
    drop index(:oauth_tokens, [:grant_reference, :client_id], name: @index_name)
  end
end

defmodule Hexpm.Repo.Migrations.TightenTrustedPublisherGrantReferenceIndex do
  use Ecto.Migration

  def up do
    drop_if_exists index(:oauth_tokens, [:grant_reference, :client_id],
                     name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index
                   )

    create unique_index(
             :oauth_tokens,
             [:grant_reference, :client_id],
             where: "grant_type = 'trusted_publisher' AND grant_reference IS NOT NULL",
             name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index
           )
  end

  def down do
    drop_if_exists index(:oauth_tokens, [:grant_reference, :client_id],
                     name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index
                   )

    create unique_index(
             :oauth_tokens,
             [:grant_reference, :client_id],
             where:
               "grant_type = 'trusted_publisher' AND revoked_at IS NULL AND grant_reference IS NOT NULL",
             name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index
           )
  end
end

defmodule Hexpm.Repo.Migrations.AddTrustedPublisherToOauthTokens do
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      add_if_not_exists :trusted_publisher_id,
                        references(:trusted_publishers, on_delete: :delete_all)
    end

    create_if_not_exists index(:oauth_tokens, [:trusted_publisher_id])

    # OIDC jti must never be reusable, including after token revoke/expiry.
    create_if_not_exists unique_index(
                           :oauth_tokens,
                           [:grant_reference, :client_id],
                           where: "grant_type = 'trusted_publisher' AND grant_reference IS NOT NULL",
                           name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index
                         )

    drop_if_exists constraint(:oauth_tokens, :user_or_organization_required)

    create constraint(:oauth_tokens, :user_or_organization_or_trusted_publisher_required,
             check:
               "user_id IS NOT NULL OR organization_id IS NOT NULL OR trusted_publisher_id IS NOT NULL"
           )
  end

  def down do
    drop_if_exists constraint(:oauth_tokens, :user_or_organization_or_trusted_publisher_required)

    create constraint(:oauth_tokens, :user_or_organization_required,
             check: "user_id IS NOT NULL OR organization_id IS NOT NULL"
           )

    drop_if_exists index(:oauth_tokens, [:grant_reference, :client_id],
                     name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index
                   )

    drop_if_exists index(:oauth_tokens, [:trusted_publisher_id])

    alter table(:oauth_tokens) do
      remove_if_exists :trusted_publisher_id, :bigint
    end
  end
end

defmodule Hexpm.RepoBase.Migrations.AddLastAuthenticatedAtToOrganizationSsoIdentities do
  use Ecto.Migration

  def up do
    alter table(:organization_sso_identities) do
      add :last_authenticated_at, :utc_datetime_usec
    end

    execute("""
    UPDATE organization_sso_identities AS identity
    SET last_authenticated_at = latest.authenticated_at
    FROM (
      SELECT identity_id, max(authenticated_at) AS authenticated_at
      FROM organization_sso_sessions
      GROUP BY identity_id
    ) AS latest
    WHERE latest.identity_id = identity.id
    """)
  end

  def down do
    alter table(:organization_sso_identities) do
      remove :last_authenticated_at
    end
  end
end

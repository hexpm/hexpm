defmodule Hexpm.RepoBase.Migrations.AddEnforcementToOrganizationSsoConnections do
  use Ecto.Migration

  def change do
    alter table(:organization_sso_connections) do
      add :enforcement_mode, :text, null: false, default: "optional"

      # Until this passes the organization is enforced as if it were in pilot,
      # so scheduling required mode does not start refusing people on save.
      add :required_at, :utc_datetime_usec

      add :session_lifetime_seconds, :integer, null: false, default: 86_400

      # NULL means the organization has not chosen, which required mode does not
      # allow. Personal keys are static credentials with nothing to expire them,
      # so an organization either closes that path or knows it left it open.
      add :personal_keys, :text
    end

    create constraint(:organization_sso_connections, :organization_sso_enforcement_mode,
             check: "enforcement_mode IN ('optional', 'pilot', 'required')"
           )

    create constraint(:organization_sso_connections, :organization_sso_personal_keys,
             check: "personal_keys IS NULL OR personal_keys IN ('block', 'allow')"
           )

    create constraint(:organization_sso_connections, :organization_sso_required_personal_keys,
             check: "enforcement_mode <> 'required' OR personal_keys IS NOT NULL"
           )

    create constraint(:organization_sso_connections, :organization_sso_session_lifetime,
             check: "session_lifetime_seconds BETWEEN 3600 AND 2592000"
           )
  end
end

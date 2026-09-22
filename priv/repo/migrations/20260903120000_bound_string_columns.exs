defmodule Hexpm.Repo.Migrations.BoundStringColumns do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE packages
    SET meta = jsonb_set(
      meta,
      '{licenses}',
      (SELECT jsonb_agg(left(license, 255)) FROM jsonb_array_elements_text(meta->'licenses') AS license)
    )
    WHERE jsonb_typeof(meta->'licenses') = 'array'
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements_text(meta->'licenses') AS license
        WHERE octet_length(license) > 255
      )
    """)

    alter table(:organization_invitations) do
      modify :email, :string, size: 255
    end

    alter table(:organization_sso_identities) do
      modify :subject, :string, size: 255
      modify :provider_email, :string, size: 255
    end

    alter table(:organization_sso_transactions) do
      modify :subject, :string, size: 255
      modify :provider_email, :string, size: 255
    end

    alter table(:keys) do
      modify :name, :string, size: 255
    end

    alter table(:users) do
      modify :full_name, :string, size: 255
    end

    alter table(:organization_domains) do
      modify :domain, :string, size: 253
    end

    alter table(:package_reports) do
      modify :summary, :string, size: 200
    end

    alter table(:policies) do
      modify :description, :string, size: 500
    end

    alter table(:security_advisory_references) do
      modify :url, :string, size: 2000
    end
  end

  def down do
    alter table(:organization_invitations) do
      modify :email, :text
    end

    alter table(:organization_sso_identities) do
      modify :subject, :text
      modify :provider_email, :text
    end

    alter table(:organization_sso_transactions) do
      modify :subject, :text
      modify :provider_email, :text
    end

    alter table(:keys) do
      modify :name, :text
    end

    alter table(:users) do
      modify :full_name, :text
    end

    alter table(:organization_domains) do
      modify :domain, :text
    end

    alter table(:package_reports) do
      modify :summary, :text
    end

    alter table(:policies) do
      modify :description, :text
    end

    alter table(:security_advisory_references) do
      modify :url, :string, size: 255
    end
  end
end

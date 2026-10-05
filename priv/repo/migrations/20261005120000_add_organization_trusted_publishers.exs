defmodule Hexpm.Repo.Migrations.AddOrganizationTrustedPublishers do
  use Ecto.Migration

  def change do
    alter table(:trusted_publishers) do
      modify :package_id, :bigint, null: true, from: {:bigint, null: false}
      add :organization_id, references(:organizations, on_delete: :delete_all)
      add :role, :string, null: false, default: "write"
      add :packages, {:array, :text}
    end

    create constraint(:trusted_publishers, :trusted_publishers_package_or_organization,
             check: "(package_id IS NULL) <> (organization_id IS NULL)"
           )

    create constraint(:trusted_publishers, :trusted_publishers_role,
             check: "role IN ('read', 'write') AND (package_id IS NULL OR role = 'write')"
           )

    # Null, not an empty list, means every package.
    create constraint(:trusted_publishers, :trusted_publishers_packages,
             check:
               "packages IS NULL OR " <>
                 "(organization_id IS NOT NULL AND role = 'write' AND cardinality(packages) > 0)"
           )

    # An empty workflow matches every workflow in the repository, and an empty
    # repository every repository the owner has. Only an organization publisher
    # that fetches may leave either empty.
    create constraint(:trusted_publishers, :trusted_publishers_workflow,
             check: "workflow <> '' OR (organization_id IS NOT NULL AND role = 'read')"
           )

    create constraint(:trusted_publishers, :trusted_publishers_repository,
             check:
               "(repository <> '' AND repository_id <> '') OR " <>
                 "(repository = '' AND repository_id = '' AND workflow = '' AND " <>
                 "environment = '' AND organization_id IS NOT NULL AND role = 'read')"
           )

    create unique_index(
             :trusted_publishers,
             [
               :organization_id,
               :provider,
               :repository_owner_id,
               :repository,
               :workflow,
               "lower(environment)"
             ],
             where: "organization_id IS NOT NULL",
             name: :trusted_publishers_organization_config_unique
           )
  end
end

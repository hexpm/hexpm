defmodule Hexpm.Repo.Migrations.AddOrganizationWorkloadIdentities do
  use Ecto.Migration

  def change do
    alter table(:workload_identities) do
      modify :package_id, :bigint, null: true, from: {:bigint, null: false}
      add :organization_id, references(:organizations, on_delete: :delete_all)
      add :role, :string, null: false, default: "write"
      add :packages, {:array, :text}
    end

    create constraint(:workload_identities, :workload_identities_package_or_organization,
             check: "(package_id IS NULL) <> (organization_id IS NULL)"
           )

    create constraint(:workload_identities, :workload_identities_role,
             check: "role IN ('read', 'write') AND (package_id IS NULL OR role = 'write')"
           )

    # Null, not an empty list, means every package.
    create constraint(:workload_identities, :workload_identities_packages,
             check:
               "packages IS NULL OR " <>
                 "(organization_id IS NOT NULL AND role = 'write' AND cardinality(packages) > 0)"
           )

    # An empty workflow matches every workflow in the repository, and an empty
    # repository every repository the owner has. Only an organization publisher
    # that fetches may leave either empty.
    create constraint(:workload_identities, :workload_identities_workflow,
             check: "workflow <> '' OR (organization_id IS NOT NULL AND role = 'read')"
           )

    create constraint(:workload_identities, :workload_identities_repository,
             check:
               "(repository <> '' AND repository_id <> '') OR " <>
                 "(repository = '' AND repository_id = '' AND workflow = '' AND " <>
                 "environment = '' AND organization_id IS NOT NULL AND role = 'read')"
           )

    create unique_index(
             :workload_identities,
             [
               :organization_id,
               :provider,
               :repository_owner_id,
               :repository,
               :workflow,
               "lower(environment)"
             ],
             where: "organization_id IS NOT NULL",
             name: :workload_identities_organization_config_unique
           )
  end
end

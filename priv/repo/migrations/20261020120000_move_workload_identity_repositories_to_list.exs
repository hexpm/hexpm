defmodule Hexpm.Repo.Migrations.MoveWorkloadIdentityRepositoriesToList do
  use Ecto.Migration

  # Every element is an object that names a repository as "owner/name" and
  # pins its immutable ID. The lax path reads the fields, and would unwrap a
  # nested array, so the strict path checks that every element is an object.
  @non_object ~S"""
  strict $[*] ? (@.type() != "object")
  """

  @invalid_repository ~S"""
  lax $[*] ? (!(exists(@.name)) || !(exists(@.id)) || @.name.type() != "string" ||
    @.id.type() != "string" || @.name == "" || @.id == "")
  """

  def up do
    alter table(:workload_identities) do
      add :repositories, :jsonb, null: false, default: "[]"
    end

    execute """
    UPDATE workload_identities
    SET repositories = jsonb_build_array(jsonb_build_object('name', repository, 'id', repository_id))
    WHERE repository <> ''
    """

    drop constraint(:workload_identities, :workload_identities_repository)
    drop index(:workload_identities, [], name: :workload_identities_package_config_unique)
    drop index(:workload_identities, [], name: :workload_identities_organization_config_unique)

    alter table(:workload_identities) do
      remove :repository
      remove :repository_id
    end

    # An empty list matches every repository the owner has, which only an
    # organization workload identity that fetches may do, and then neither the
    # workflow nor the environment narrows it.
    create constraint(:workload_identities, :workload_identities_repositories,
             check:
               "jsonb_typeof(repositories) = 'array' AND " <>
                 "NOT jsonb_path_exists(repositories, $$#{@non_object}$$) AND " <>
                 "NOT jsonb_path_exists(repositories, $$#{@invalid_repository}$$) AND " <>
                 "(jsonb_array_length(repositories) > 0 OR " <>
                 "(workflow = '' AND environment = '' AND organization_id IS NOT NULL AND " <>
                 "role = 'read'))"
           )
  end

  def down do
    # The previous schema has one repository per workload identity. Identities
    # with more are deleted and their tokens revoked.
    execute """
    UPDATE oauth_tokens
    SET revoked_at = now(), updated_at = now()
    WHERE revoked_at IS NULL
      AND workload_identity_id IN (
        SELECT id FROM workload_identities WHERE jsonb_array_length(repositories) > 1
      )
    """

    execute "DELETE FROM workload_identities WHERE jsonb_array_length(repositories) > 1"

    drop constraint(:workload_identities, :workload_identities_repositories)

    alter table(:workload_identities) do
      add :repository, :string, null: false, default: ""
      add :repository_id, :string, null: false, default: ""
    end

    execute """
    UPDATE workload_identities
    SET repository = repositories -> 0 ->> 'name', repository_id = repositories -> 0 ->> 'id'
    WHERE jsonb_array_length(repositories) = 1
    """

    alter table(:workload_identities) do
      modify :repository, :string, null: false, default: nil
      modify :repository_id, :string, null: false, default: nil
      remove :repositories
    end

    # The previous schema allows one workload identity per configuration, so
    # later duplicates are deleted the same way.
    delete_duplicates(
      "package_id IS NOT NULL",
      "package_id, provider, repository, workflow, lower(environment)"
    )

    delete_duplicates(
      "organization_id IS NOT NULL",
      "organization_id, provider, repository_owner_id, repository, workflow, lower(environment)"
    )

    create constraint(:workload_identities, :workload_identities_repository,
             check:
               "(repository <> '' AND repository_id <> '') OR " <>
                 "(repository = '' AND repository_id = '' AND workflow = '' AND " <>
                 "environment = '' AND organization_id IS NOT NULL AND role = 'read')"
           )

    create unique_index(
             :workload_identities,
             [:package_id, :provider, :repository, :workflow, "lower(environment)"],
             name: :workload_identities_package_config_unique
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

  defp delete_duplicates(where, columns) do
    duplicates = """
    SELECT id FROM (
      SELECT id, row_number() OVER (PARTITION BY #{columns} ORDER BY id) AS position
      FROM workload_identities
      WHERE #{where}
    ) ranked
    WHERE position > 1
    """

    execute """
    UPDATE oauth_tokens
    SET revoked_at = now(), updated_at = now()
    WHERE revoked_at IS NULL AND workload_identity_id IN (#{duplicates})
    """

    execute "DELETE FROM workload_identities WHERE id IN (#{duplicates})"
  end
end

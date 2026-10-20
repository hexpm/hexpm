defmodule Hexpm.Repo.Migrations.AddPublicCoverageToWorkloadIdentities do
  use Ecto.Migration

  def up do
    alter table(:workload_identities) do
      add :covers_private, :boolean, null: false, default: true
      add :covers_public, :boolean, null: false, default: false
      add :public_packages, {:array, :text}
    end

    drop constraint(:workload_identities, :workload_identities_packages)

    # Null, not an empty list, means every package. An identity that covers no
    # private package stores an empty list, which covers nothing for code that
    # only reads the list.
    create constraint(:workload_identities, :workload_identities_packages,
             check:
               "packages IS NULL OR " <>
                 "(organization_id IS NOT NULL AND role = 'write' AND " <>
                 "(cardinality(packages) > 0) = covers_private)"
           )

    create constraint(:workload_identities, :workload_identities_private_coverage,
             check:
               "covers_private OR " <>
                 "(packages IS NOT NULL AND cardinality(packages) = 0 AND covers_public)"
           )

    create constraint(:workload_identities, :workload_identities_public_coverage,
             check: "NOT covers_public OR (organization_id IS NOT NULL AND role = 'write')"
           )

    # Null means every public package the organization owns.
    create constraint(:workload_identities, :workload_identities_public_packages,
             check:
               "public_packages IS NULL OR (covers_public AND cardinality(public_packages) > 0)"
           )
  end

  def down do
    # The previous schema has no way to store an identity without private
    # coverage: an empty list fails its constraint and null covers every
    # private package. Those identities are deleted and their tokens revoked
    # instead.
    execute """
    UPDATE oauth_tokens
    SET revoked_at = now(), updated_at = now()
    WHERE revoked_at IS NULL
      AND workload_identity_id IN (SELECT id FROM workload_identities WHERE NOT covers_private)
    """

    execute "DELETE FROM workload_identities WHERE NOT covers_private"

    drop constraint(:workload_identities, :workload_identities_public_packages)
    drop constraint(:workload_identities, :workload_identities_public_coverage)
    drop constraint(:workload_identities, :workload_identities_private_coverage)
    drop constraint(:workload_identities, :workload_identities_packages)

    create constraint(:workload_identities, :workload_identities_packages,
             check:
               "packages IS NULL OR " <>
                 "(organization_id IS NOT NULL AND role = 'write' AND cardinality(packages) > 0)"
           )

    alter table(:workload_identities) do
      remove :public_packages
      remove :covers_public
      remove :covers_private
    end
  end
end

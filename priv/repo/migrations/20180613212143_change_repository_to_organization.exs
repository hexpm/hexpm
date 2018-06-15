defmodule Hexpm.Repo.Migrations.ChangeRepositoryToOrganization do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE repositories RENAME TO organizations")
    execute("ALTER INDEX repositories_pkey RENAME TO organizations_pkey")
    execute("ALTER INDEX repositories_name_index RENAME TO organizations_name_index")
    execute("ALTER INDEX repositories_public_index RENAME TO organizations_public_index")

    execute("ALTER TABLE repository_users RENAME TO organization_users")
    execute("ALTER TABLE organization_users RENAME repository_id TO organization_id")
    execute("ALTER INDEX repository_users_pkey RENAME TO organization_users_pkey")

    execute(
      "ALTER INDEX repository_users_repository_id_user_id_index RENAME TO organization_users_organization_id_user_id_index"
    )

    execute(
      "ALTER INDEX repository_users_user_id_index RENAME TO organization_users_user_id_index"
    )

    execute("""
    ALTER TABLE organization_users
      RENAME CONSTRAINT repository_users_repository_id_fkey TO organization_users_organization_id_fkey
    """)

    execute("""
    ALTER TABLE organization_users
      RENAME CONSTRAINT repository_users_user_id_fkey TO organization_users_user_id_fkey
    """)

    execute("ALTER TABLE packages RENAME repository_id TO organization_id")

    execute(
      "ALTER INDEX packages_repository_id_name_index RENAME TO packages_organization_id_name_index"
    )

    execute("""
    ALTER TABLE packages
      RENAME CONSTRAINT packages_repository_id_fkey TO packages_organization_id_fkey
    """)

    execute("ALTER TABLE audit_logs RENAME repository_id TO organization_id")

    execute(
      "ALTER INDEX audit_logs_repository_id_index RENAME TO audit_logs_organization_id_index"
    )

    execute("""
    ALTER TABLE audit_logs
      RENAME CONSTRAINT audit_logs_repository_id_fkey TO audit_logs_organization_id_fkey
    """)

    execute("ALTER TABLE reserved_packages RENAME repository_id TO organization_id")

    execute(
      "ALTER INDEX reserved_packages_repository_id_name_version_index RENAME TO reserved_packages_organization_id_name_version_index"
    )

    execute("""
    ALTER TABLE reserved_packages
      RENAME CONSTRAINT reserved_packages_repository_id_fkey TO reserved_packages_organization_id_fkey
    """)
  end

  def down do
    execute("ALTER TABLE organizations RENAME TO repositories")
    execute("ALTER INDEX organizations_pkey RENAME TO repositories_pkey")
    execute("ALTER INDEX organizations_name_index RENAME TO repositories_name_index")
    execute("ALTER INDEX organizations_public_index RENAME TO repositories_public_index")

    execute("ALTER TABLE organization_users RENAME TO repository_users")
    execute("ALTER TABLE repository_users RENAME organization_id TO repository_id")
    execute("ALTER INDEX organization_users_pkey RENAME TO repository_users_pkey")

    execute(
      "ALTER INDEX organization_users_organization_id_user_id_index RENAME TO repository_users_repository_id_user_id_index"
    )

    execute(
      "ALTER INDEX organization_users_user_id_index RENAME TO repository_users_user_id_index"
    )

    execute("""
    ALTER TABLE repository_users
      RENAME CONSTRAINT organization_users_organization_id_fkey TO repository_users_repository_id_fkey
    """)

    execute("""
    ALTER TABLE repository_users
      RENAME CONSTRAINT organization_users_user_id_fkey TO repository_users_user_id_fkey
    """)

    execute("ALTER TABLE packages RENAME organization_id TO repository_id")

    execute(
      "ALTER INDEX packages_organization_id_name_index RENAME TO packages_repository_id_name_index"
    )

    execute("""
    ALTER TABLE packages
      RENAME CONSTRAINT packages_organization_id_fkey TO packages_repository_id_fkey
    """)

    execute("ALTER TABLE audit_logs RENAME organization_id TO repository_id")

    execute(
      "ALTER INDEX audit_logs_organization_id_index RENAME TO audit_logs_repository_id_index"
    )

    execute("""
    ALTER TABLE audit_logs
      RENAME CONSTRAINT audit_logs_organization_id_fkey TO audit_logs_repository_id_fkey
    """)

    execute("ALTER TABLE reserved_packages RENAME organization_id TO repository_id")

    execute(
      "ALTER INDEX reserved_packages_organization_id_name_version_index RENAME TO reserved_packages_repository_id_name_version_index"
    )

    execute("""
    ALTER TABLE reserved_packages
      RENAME CONSTRAINT reserved_packages_organization_id_fkey TO reserved_packages_repository_id_fkey
    """)
  end
end

defmodule Hexpm.Repo.Migrations.AddUserDeleteConstraints do
  use Ecto.Migration

  def up() do
    # Allow NULL for author_id columns (required for SET NULL on delete)
    execute("ALTER TABLE package_reports ALTER COLUMN author_id DROP NOT NULL")
    execute("ALTER TABLE package_report_comments ALTER COLUMN author_id DROP NOT NULL")

    # Drop existing foreign key constraints
    execute("ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_actor_id_fkey")
    execute("ALTER TABLE organization_users DROP CONSTRAINT IF EXISTS organization_users_user_id_fkey")
    execute("ALTER TABLE package_reports DROP CONSTRAINT IF EXISTS package_reports_author_id_fkey")
    execute("ALTER TABLE package_report_comments DROP CONSTRAINT IF EXISTS package_report_comments_author_id_fkey")
    execute("ALTER TABLE password_resets DROP CONSTRAINT IF EXISTS password_resets_user_id_fkey")
    execute("ALTER TABLE releases DROP CONSTRAINT IF EXISTS releases_publisher_id_fkey")

    # Recreate constraints with ON DELETE actions
    execute("""
      ALTER TABLE audit_logs
        ADD CONSTRAINT audit_logs_actor_id_fkey
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
    """)

    execute("""
      ALTER TABLE organization_users
        ADD CONSTRAINT organization_users_user_id_fkey
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    """)

    execute("""
      ALTER TABLE package_reports
        ADD CONSTRAINT package_reports_author_id_fkey
          FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE SET NULL
    """)

    execute("""
      ALTER TABLE package_report_comments
        ADD CONSTRAINT package_report_comments_author_id_fkey
          FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE SET NULL
    """)

    execute("""
      ALTER TABLE password_resets
        ADD CONSTRAINT password_resets_user_id_fkey
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    """)

    execute("""
      ALTER TABLE releases
        ADD CONSTRAINT releases_publisher_id_fkey
          FOREIGN KEY (publisher_id) REFERENCES users(id) ON DELETE SET NULL
    """)
  end

  def down() do
    # Drop constraints with ON DELETE actions
    execute("ALTER TABLE audit_logs DROP CONSTRAINT audit_logs_actor_id_fkey")
    execute("ALTER TABLE organization_users DROP CONSTRAINT organization_users_user_id_fkey")
    execute("ALTER TABLE package_reports DROP CONSTRAINT package_reports_author_id_fkey")
    execute("ALTER TABLE package_report_comments DROP CONSTRAINT package_report_comments_author_id_fkey")
    execute("ALTER TABLE password_resets DROP CONSTRAINT password_resets_user_id_fkey")
    execute("ALTER TABLE releases DROP CONSTRAINT releases_publisher_id_fkey")

    # Recreate constraints without ON DELETE actions
    execute("""
      ALTER TABLE audit_logs
        ADD CONSTRAINT audit_logs_actor_id_fkey
          FOREIGN KEY (user_id) REFERENCES users(id)
    """)

    execute("""
      ALTER TABLE organization_users
        ADD CONSTRAINT organization_users_user_id_fkey
          FOREIGN KEY (user_id) REFERENCES users(id)
    """)

    execute("""
      ALTER TABLE package_reports
        ADD CONSTRAINT package_reports_author_id_fkey
          FOREIGN KEY (author_id) REFERENCES users(id)
    """)

    execute("""
      ALTER TABLE package_report_comments
        ADD CONSTRAINT package_report_comments_author_id_fkey
          FOREIGN KEY (author_id) REFERENCES users(id)
    """)

    execute("""
      ALTER TABLE password_resets
        ADD CONSTRAINT password_resets_user_id_fkey
          FOREIGN KEY (user_id) REFERENCES users(id)
    """)

    execute("""
      ALTER TABLE releases
        ADD CONSTRAINT releases_publisher_id_fkey
          FOREIGN KEY (publisher_id) REFERENCES users(id)
    """)

    # Restore NOT NULL constraints (will fail if any NULL values exist)
    execute("ALTER TABLE package_reports ALTER COLUMN author_id SET NOT NULL")
    execute("ALTER TABLE package_report_comments ALTER COLUMN author_id SET NOT NULL")
  end
end

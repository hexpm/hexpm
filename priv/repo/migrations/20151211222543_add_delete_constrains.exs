defmodule Hexpm.Repo.Migrations.AddDeleteConstraints do
  use Ecto.Migration

  def up() do
    execute("ALTER TABLE keys           DROP CONSTRAINT IF EXISTS keys_user_id_fkey")
    execute("ALTER TABLE package_owners DROP CONSTRAINT IF EXISTS package_owners_package_id_fkey")
    execute("ALTER TABLE package_owners DROP CONSTRAINT IF EXISTS package_owners_owner_id_fkey")
    execute("ALTER TABLE requirements   DROP CONSTRAINT IF EXISTS requirements_release_id_fkey")
    execute("ALTER TABLE downloads      DROP CONSTRAINT IF EXISTS downloads_release_id_fkey")

    execute("""
      ALTER TABLE keys
        ADD CONSTRAINT keys_user_id_fkey
          FOREIGN KEY (user_id) REFERENCES users ON DELETE CASCADE
    """)

    execute("""
      ALTER TABLE package_owners
        ADD CONSTRAINT package_owners_package_id_fkey
          FOREIGN KEY (package_id) REFERENCES packages ON DELETE CASCADE
    """)

    execute("""
      ALTER TABLE package_owners
        ADD CONSTRAINT package_owners_owner_id_fkey
          FOREIGN KEY (owner_id) REFERENCES users ON DELETE CASCADE
    """)

    execute("""
      ALTER TABLE requirements
        ADD CONSTRAINT requirements_release_id_fkey
          FOREIGN KEY (release_id) REFERENCES releases ON DELETE CASCADE
    """)

    execute("""
      ALTER TABLE downloads
        ADD CONSTRAINT downloads_release_id_fkey
          FOREIGN KEY (release_id) REFERENCES releases ON DELETE CASCADE
    """)
  end

  def down() do
    execute("ALTER TABLE keys           DROP CONSTRAINT keys_user_id_fkey")
    execute("ALTER TABLE package_owners DROP CONSTRAINT package_owners_package_id_fkey")
    execute("ALTER TABLE package_owners DROP CONSTRAINT package_owners_owner_id_fkey")
    execute("ALTER TABLE requirements   DROP CONSTRAINT requirements_release_id_fkey")
    execute("ALTER TABLE downloads      DROP CONSTRAINT downloads_release_id_fkey")

    execute("""
      ALTER TABLE keys
        ADD CONSTRAINT keys_user_id_fkey
          FOREIGN KEY (user_id) REFERENCES users
    """)

    execute("""
      ALTER TABLE package_owners
        ADD CONSTRAINT package_owners_package_id_fkey
          FOREIGN KEY (package_id) REFERENCES packages
    """)

    execute("""
      ALTER TABLE package_owners
        ADD CONSTRAINT package_owners_owner_id_fkey
          FOREIGN KEY (owner_id) REFERENCES users
    """)

    execute("""
      ALTER TABLE requirements
        ADD CONSTRAINT requirements_release_id_fkey
          FOREIGN KEY (release_id) REFERENCES releases
    """)

    execute("""
      ALTER TABLE downloads
        ADD CONSTRAINT downloads_release_id_fkey
          FOREIGN KEY (release_id) REFERENCES releases
    """)
  end
end

defmodule Hexpm.Repo.Migrations.AddTimestampsToPackageOwners do
  use Ecto.Migration

  def change do
    execute("""
    ALTER TABLE package_owners
      ADD inserted_at timestamp DEFAULT now(),
      ADD updated_at timestamp DEFAULT now()
    """)

    execute("""
    ALTER TABLE package_owners
      ALTER inserted_at DROP DEFAULT,
      ALTER updated_at DROP DEFAULT
    """)
  end
end

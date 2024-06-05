defmodule Hexpm.RepoBase.Migrations.CreateStoredProcedureToPurgePackageSearches do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE PROCEDURE purge_package_searches()
    LANGUAGE SQL
    AS $$
    DELETE FROM package_searches
    WHERE inserted_at < NOW() - INTERVAL '1 month'
    AND frequency < 2;
    $$;
    """
  end

  def down do
    execute "DROP PROCEDURE IF EXISTS purge_package_searches"
  end
end

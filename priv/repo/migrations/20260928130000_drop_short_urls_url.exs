defmodule Hexpm.Repo.Migrations.DropShortURLsURL do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO short_url_targets (url, url_hash, inserted_at)
    SELECT DISTINCT url, sha256(convert_to(url, 'UTF8')), now() AT TIME ZONE 'UTC'
    FROM short_urls
    WHERE target_id IS NULL
    ON CONFLICT (url_hash) DO NOTHING
    """)

    execute("""
    UPDATE short_urls AS s
    SET target_id = t.id
    FROM short_url_targets AS t
    WHERE s.target_id IS NULL AND t.url_hash = sha256(convert_to(s.url, 'UTF8'))
    """)

    alter table(:short_urls) do
      modify :target_id, :bigint, null: false, from: {:bigint, null: true}
      remove :url
    end
  end

  def down do
    alter table(:short_urls) do
      add :url, :text
      modify :target_id, :bigint, null: true, from: {:bigint, null: false}
    end

    execute("""
    UPDATE short_urls AS s
    SET url = t.url
    FROM short_url_targets AS t
    WHERE t.id = s.target_id
    """)
  end
end

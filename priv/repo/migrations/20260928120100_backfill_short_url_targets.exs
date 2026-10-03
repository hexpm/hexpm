defmodule Hexpm.Repo.Migrations.BackfillShortURLTargets do
  use Ecto.Migration

  alias Hexpm.ShortURLs.{ShortURL, Target}

  @disable_ddl_transaction true

  def up do
    backfill(repo())
  end

  def down do
    :ok
  end

  @doc """
  Points every short URL without a target at the target for the canonical form
  of its URL, creating targets as needed. A URL that is not a valid diff link
  becomes its own target unchanged.

  Runs in batches of `:batch_size` rows, each statement in its own transaction.
  """
  def backfill(repo, opts \\ []) do
    backfill(repo, Keyword.get(opts, :batch_size, 5_000), 0)
  end

  defp backfill(repo, batch_size, last_id) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT id, url FROM short_urls
        WHERE target_id IS NULL AND id > $1
        ORDER BY id
        LIMIT $2
        """,
        [last_id, batch_size]
      )

    if rows == [] do
      :ok
    else
      rows =
        Enum.map(rows, fn [id, url] ->
          url = target_url(url)
          {id, url, Target.url_hash(url)}
        end)

      targets = Enum.uniq_by(rows, fn {_id, _url, hash} -> hash end)

      repo.query!(
        """
        INSERT INTO short_url_targets (url, url_hash, inserted_at)
        SELECT url, url_hash, now() AT TIME ZONE 'UTC'
        FROM unnest($1::text[], $2::bytea[]) AS t(url, url_hash)
        ON CONFLICT (url_hash) DO NOTHING
        """,
        [Enum.map(targets, &elem(&1, 1)), Enum.map(targets, &elem(&1, 2))]
      )

      repo.query!(
        """
        UPDATE short_urls AS s
        SET target_id = t.id
        FROM unnest($1::bigint[], $2::bytea[]) AS v(id, url_hash)
        JOIN short_url_targets AS t ON t.url_hash = v.url_hash
        WHERE s.id = v.id
        """,
        [Enum.map(rows, &elem(&1, 0)), Enum.map(rows, &elem(&1, 2))]
      )

      {last_id, _url, _hash} = List.last(rows)
      backfill(repo, batch_size, last_id)
    end
  end

  defp target_url(url) do
    case ShortURL.canonical_diff_url(url) do
      {:ok, canonical, _packages} -> canonical
      {:error, _reason} -> url
    end
  end
end

defmodule Hexpm.Emails.OutboxReconciler do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 10,
    unique: [period: :infinity, states: :incomplete]

  import Ecto.Query, only: [from: 2]

  alias Hexpm.Emails.{OutboxEntry, OutboxWorker}
  alias Hexpm.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    discard_terminal_entries()
    purge_expired()
    reconcile_heads()
    :ok
  end

  defp discard_terminal_entries do
    worker = inspect(OutboxWorker)

    from(job in Oban.Job,
      where: job.worker == ^worker,
      where: job.state == "discarded",
      where: job.attempt >= job.max_attempts,
      where:
        fragment(
          """
          EXISTS (
            SELECT 1
            FROM email_outbox_entries AS entry
            WHERE entry.id = (?->>'outbox_entry_id')::bigint
          )
          """,
          job.args
        ),
      select: fragment("(?->>'outbox_entry_id')::bigint", job.args),
      order_by: [asc: job.id],
      limit: 500
    )
    |> Repo.all()
    |> Enum.each(&OutboxWorker.discard!/1)
  end

  defp purge_expired do
    now = DateTime.utc_now()

    {:ok, entries} =
      Repo.transaction(fn ->
        entries =
          from(entry in OutboxEntry,
            where: not is_nil(entry.expires_at),
            where: entry.expires_at <= ^now,
            order_by: [asc: entry.id],
            select: %{category: entry.category, outbox_entry_id: entry.id},
            limit: 500,
            lock: "FOR UPDATE SKIP LOCKED"
          )
          |> Repo.all()

        ids = Enum.map(entries, & &1.outbox_entry_id)
        Repo.delete_all(from(entry in OutboxEntry, where: entry.id in ^ids))
        entries
      end)

    if entries != [] do
      Sentry.capture_message("Expired email outbox entries were discarded",
        extra: %{
          count: length(entries),
          categories: Enum.frequencies_by(entries, & &1.category)
        }
      )
    end
  end

  defp reconcile_heads do
    incomplete_states =
      Oban.Job.unique_states(:incomplete)
      |> Enum.map(&Atom.to_string/1)

    worker = inspect(OutboxWorker)

    from(entry in OutboxEntry,
      where:
        is_nil(entry.ordering_key) or
          fragment(
            """
            NOT EXISTS (
              SELECT 1
              FROM email_outbox_entries AS earlier
              WHERE earlier.ordering_key = ?
                AND earlier.id < ?
            )
            """,
            entry.ordering_key,
            entry.id
          ),
      where:
        fragment(
          """
          NOT EXISTS (
            SELECT 1
            FROM oban_jobs AS job
            WHERE job.worker = ?
              AND job.args @> jsonb_build_object('outbox_entry_id', ?)
              AND (
                job.state = ANY(?)
                OR (
                  job.state = 'discarded'
                  AND job.attempt >= job.max_attempts
                )
              )
          )
          """,
          ^worker,
          entry.id,
          ^incomplete_states
        ),
      order_by: [asc: entry.id],
      select: entry.id,
      limit: 500
    )
    |> Repo.all()
    |> Enum.each(&OutboxWorker.enqueue!/1)
  end
end

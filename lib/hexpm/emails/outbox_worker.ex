defmodule Hexpm.Emails.OutboxWorker do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 10,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  import Ecto.Query, only: [from: 2]

  alias Hexpm.Emails.{Mailer, OutboxEntry, OutboxLock}
  alias Hexpm.Repo

  def enqueue_if_head!(%OutboxEntry{ordering_key: nil} = entry), do: enqueue!(entry.id)

  def enqueue_if_head!(%OutboxEntry{} = entry) do
    unless earlier_entry?(entry), do: enqueue!(entry.id)
  end

  def enqueue!(outbox_entry_id) do
    %{outbox_entry_id: outbox_entry_id}
    |> new()
    |> Oban.insert!()
  end

  def discard!(outbox_entry_id), do: discard_entry(outbox_entry_id)

  @impl Oban.Worker
  def timeout(%Oban.Job{}), do: :timer.seconds(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"outbox_entry_id" => outbox_entry_id}} = job) do
    perform_entry(outbox_entry_id)
  rescue
    exception ->
      if job.attempt >= job.max_attempts do
        discard_entry(outbox_entry_id)
      end

      reraise exception, __STACKTRACE__
  end

  defp perform_entry(outbox_entry_id) do
    Repo.transaction(fn ->
      case Repo.get(OutboxEntry, outbox_entry_id) do
        nil ->
          :ok

        target ->
          OutboxLock.acquire!(target.ordering_key)
          entry = target |> oldest_entry_query() |> Repo.one()

          case entry do
            %OutboxEntry{id: id} when id == target.id ->
              deliver_or_expire!(entry)
              Repo.delete!(entry)
              enqueue_next!(entry)
              :ok

            %OutboxEntry{} ->
              :ok

            nil ->
              :ok
          end
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp oldest_entry_query(%OutboxEntry{ordering_key: nil, id: id}) do
    from(entry in OutboxEntry,
      where: entry.id == ^id,
      lock: "FOR UPDATE"
    )
  end

  defp oldest_entry_query(%OutboxEntry{ordering_key: ordering_key}) do
    from(entry in OutboxEntry,
      where: entry.ordering_key == ^ordering_key,
      order_by: [asc: entry.id],
      limit: 1,
      lock: "FOR UPDATE"
    )
  end

  defp earlier_entry?(entry) do
    Repo.exists?(
      from(candidate in OutboxEntry,
        where: candidate.ordering_key == ^entry.ordering_key,
        where: candidate.id < ^entry.id
      )
    )
  end

  defp enqueue_next!(%OutboxEntry{ordering_key: nil}), do: :ok

  defp enqueue_next!(%OutboxEntry{ordering_key: ordering_key}) do
    from(entry in OutboxEntry,
      where: entry.ordering_key == ^ordering_key,
      order_by: [asc: entry.id],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> :ok
      entry -> enqueue!(entry.id)
    end
  end

  defp discard_entry(outbox_entry_id) do
    discarded =
      Repo.transaction(fn ->
        Repo.get(OutboxEntry, outbox_entry_id)
        |> case do
          nil ->
            nil

          target ->
            OutboxLock.acquire!(target.ordering_key)

            from(entry in OutboxEntry,
              where: entry.id == ^outbox_entry_id,
              lock: "FOR UPDATE"
            )
            |> Repo.one()
            |> case do
              nil ->
                nil

              entry ->
                Repo.delete!(entry)
                enqueue_next!(entry)
                %{category: entry.category, outbox_entry_id: entry.id}
            end
        end
      end)

    case discarded do
      {:ok, nil} ->
        :ok

      {:ok, extra} ->
        Sentry.capture_message("Email outbox entry discarded after repeated delivery failures",
          extra: extra
        )

      {:error, _reason} ->
        :ok
    end
  end

  defp deliver_or_expire!(%OutboxEntry{expires_at: nil} = entry), do: deliver!(entry)

  defp deliver_or_expire!(%OutboxEntry{expires_at: expires_at} = entry) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt, do: deliver!(entry)
  end

  defp deliver!(entry) do
    entry
    |> OutboxEntry.to_email()
    |> Mailer.deliver!()
  end
end

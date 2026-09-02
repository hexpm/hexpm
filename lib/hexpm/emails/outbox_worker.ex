defmodule Hexpm.Emails.OutboxWorker do
  use Oban.Worker,
    queue: :email,
    max_attempts: 10,
    unique: [period: :infinity, states: :incomplete, fields: [:worker, :args]]

  import Ecto.Query, only: [from: 2]

  alias Hexpm.Emails.{Mailer, OutboxEntry, OutboxEnvelope}
  alias Hexpm.Repo
  alias Swoosh.Email

  def enqueue!(outbox_entry_id, opts \\ []) do
    %{outbox_entry_id: outbox_entry_id}
    |> new(priority: Keyword.get(opts, :priority, 0))
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
      case locked_entry(outbox_entry_id) do
        nil ->
          :ok

        entry ->
          Logger.metadata(outbox_entry_id: entry.id, outbox_category: entry.category)

          case deliver_or_expire!(entry) do
            {:delivered, result} -> record_delivery!(entry, result)
            :expired -> Repo.delete!(entry)
          end

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Delivery runs inside the transaction so that a failed commit leaves the entry
  # to be retried rather than recorded as delivered. The row lock is held across
  # it, which is why cancellation skips locked rows instead of waiting for them.
  defp locked_entry(outbox_entry_id) do
    from(entry in OutboxEntry.undelivered(),
      where: entry.id == ^outbox_entry_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp discard_entry(outbox_entry_id) do
    discarded =
      Repo.transaction(fn ->
        case locked_entry(outbox_entry_id) do
          nil ->
            nil

          entry ->
            Repo.delete!(entry)
            %{category: entry.category, outbox_entry_id: entry.id}
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

  defp deliver_or_expire!(%OutboxEntry{expires_at: nil} = entry) do
    {:delivered, deliver!(entry)}
  end

  defp deliver_or_expire!(%OutboxEntry{expires_at: expires_at} = entry) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      {:delivered, deliver!(entry)}
    else
      :expired
    end
  end

  defp record_delivery!(entry, result) do
    entry
    |> Ecto.Changeset.change(
      delivered_at: DateTime.utc_now(),
      provider_message_id: provider_message_id(result)
    )
    |> Repo.update!()
  end

  defp provider_message_id(%{id: id}) when is_binary(id), do: id
  defp provider_message_id(_result), do: nil

  defp deliver!(entry) do
    email = OutboxEnvelope.load!(entry.email)

    email
    |> Email.header("Message-ID", message_id(entry, email))
    |> Mailer.deliver!()
  end

  # SendGrid has no idempotency key, so a retry after it accepted the mail but
  # the transaction failed to commit sends the same mail again. A Message-ID
  # tied to the entry is the only thing that lets the receiving server drop it.
  defp message_id(entry, %Email{from: {_name, address}}) do
    "<outbox-#{entry.id}@#{sender_domain(address)}>"
  end

  defp sender_domain(address) do
    case String.split(address, "@", parts: 2) do
      [_local, domain] -> domain
      [local] -> local
    end
  end
end

defmodule Hexpm.Emails.Outbox do
  import Ecto.Query, only: [from: 2]

  alias Hexpm.Emails.{OutboxEntry, OutboxEnvelope, OutboxLock, OutboxWorker}
  alias Hexpm.Repo

  @allowed_options [:category, :group_key, :scope_key, :expires_at, :priority]
  @cancel_options [:group_key, :scope_key, :categories]
  @retention_seconds 30 * 24 * 60 * 60
  @insert_chunk_size 1_000
  @entry_fields ~w(category type group_key scope_key recipients subject email expires_at priority)a

  def enqueue!(%Swoosh.Email{} = email, opts) do
    email
    |> prepare!(Keyword.put_new(opts, :expires_at, default_expires_at()))
    |> insert!()
  end

  @doc """
  When a queued mail stops being worth delivering. One nothing has delivered or
  cancelled by then is stale enough that sending it would confuse its recipient
  more than dropping it would.
  """
  def default_expires_at, do: DateTime.add(DateTime.utc_now(), @retention_seconds, :second)

  # Split from insert!/1 so a caller enqueueing inside its own transaction can
  # put the part that raises on a malformed email before the part that issues
  # SQL, and rescue only the first.
  def prepare!(%Swoosh.Email{} = email, opts) do
    attrs = Map.new(opts)
    validate_options!(attrs)

    attrs
    |> Map.put(:email, OutboxEnvelope.dump!(email))
    |> Map.put(:type, email.private[:type])
    |> Map.put(:recipients, recipients(email))
    |> Map.put(:subject, email.subject)
  end

  defp recipients(%Swoosh.Email{to: to, cc: cc, bcc: bcc}) do
    Enum.map(to ++ cc ++ bcc, fn {_name, address} -> address end)
  end

  def insert!(attrs) do
    {:ok, entry} =
      Repo.transaction(fn ->
        OutboxLock.acquire!(attrs[:group_key])

        entry =
          %OutboxEntry{}
          |> OutboxEntry.changeset(attrs)
          |> Repo.insert!(log: false)

        OutboxWorker.enqueue!(entry.id, priority: entry.priority)
        entry
      end)

    entry
  end

  @doc """
  Inserts prepared entries and their delivery jobs in chunks, one statement per
  table and chunk. Returns the number of entries inserted.
  """
  def insert_all!(attrs_list) do
    {:ok, count} =
      Repo.transaction(fn ->
        attrs_list
        |> Enum.map(& &1[:group_key])
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.each(&OutboxLock.acquire!/1)

        attrs_list
        |> Enum.chunk_every(@insert_chunk_size)
        |> Enum.map(&insert_chunk!/1)
        |> Enum.sum()
      end)

    count
  end

  defp insert_chunk!(attrs_list) do
    inserted_at = DateTime.utc_now()

    rows =
      Enum.map(attrs_list, fn attrs ->
        %OutboxEntry{}
        |> OutboxEntry.changeset(attrs)
        |> Ecto.Changeset.apply_action!(:insert)
        |> Map.take(@entry_fields)
        |> Map.put(:inserted_at, inserted_at)
      end)

    {count, entries} =
      Repo.insert_all(OutboxEntry, rows, returning: [:id, :priority], log: false)

    OutboxWorker.enqueue_all!(entries)
    count
  end

  @doc """
  Cancels queued mail in the given categories, as a step on the caller's multi.

  Takes either `:group_key` for one group or `:scope_key` for every group under
  that scope, plus the `:categories` to cancel. Returns the number of entries
  deleted.
  """
  def cancel(multi, name, opts) do
    Ecto.Multi.run(multi, name, fn repo, _changes -> {:ok, cancel!(repo, opts)} end)
  end

  @doc """
  Cancels queued mail in the given categories, inside the caller's transaction.
  """
  def cancel!(opts), do: cancel!(Repo, opts)

  def cancel!(repo, opts) do
    attrs = Map.new(opts)
    validate_cancel_options!(attrs)
    categories = Map.fetch!(attrs, :categories)
    scope = cancel_scope(attrs)

    acquire_locks!(repo, scope, categories)

    # A delivery holds the entry's row lock across the call to the mail
    # provider, so waiting for it would stall the caller behind that provider.
    # Skipping is also the honest answer: mail already on its way out cannot be
    # cancelled.
    ids =
      from(entry in cancel_query(scope),
        where: entry.category in ^categories,
        select: entry.id,
        lock: "FOR UPDATE SKIP LOCKED"
      )
      |> repo.all()

    {count, _} = repo.delete_all(from(entry in OutboxEntry, where: entry.id in ^ids))
    count
  end

  defp acquire_locks!(_repo, {:group_key, group_key}, _categories) do
    OutboxLock.acquire!(group_key)
  end

  # One lock per group the scope reaches, taken in a sorted order so two
  # callers cancelling overlapping groups cannot deadlock against each other.
  defp acquire_locks!(repo, {:scope_key, scope_key}, categories) do
    from(entry in OutboxEntry.undelivered(),
      where: entry.scope_key == ^scope_key,
      where: entry.category in ^categories,
      select: entry.group_key,
      distinct: true,
      order_by: entry.group_key
    )
    |> repo.all()
    |> Enum.each(&OutboxLock.acquire!/1)
  end

  defp cancel_query({:group_key, group_key}) do
    from(entry in OutboxEntry.undelivered(), where: entry.group_key == ^group_key)
  end

  defp cancel_query({:scope_key, scope_key}) do
    from(entry in OutboxEntry.undelivered(), where: entry.scope_key == ^scope_key)
  end

  defp cancel_scope(%{group_key: group_key, scope_key: scope_key})
       when not is_nil(group_key) and not is_nil(scope_key) do
    raise ArgumentError, "email outbox cancellation takes group_key or scope_key, not both"
  end

  defp cancel_scope(%{group_key: group_key}), do: {:group_key, group_key}
  defp cancel_scope(%{scope_key: scope_key}), do: {:scope_key, scope_key}

  defp cancel_scope(_attrs) do
    raise ArgumentError, "email outbox cancellation requires group_key or scope_key"
  end

  defp validate_options!(attrs), do: validate_keys!(attrs, @allowed_options)

  defp validate_cancel_options!(attrs) do
    validate_keys!(attrs, @cancel_options)

    unless Map.has_key?(attrs, :categories) do
      raise ArgumentError, "email outbox cancellation requires categories"
    end
  end

  defp validate_keys!(attrs, allowed) do
    case Map.keys(attrs) -- allowed do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown email outbox options: #{inspect(unknown)}"
    end
  end
end

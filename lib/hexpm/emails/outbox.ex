defmodule Hexpm.Emails.Outbox do
  import Ecto.Query, only: [from: 2]

  alias Hexpm.Emails.{OutboxEntry, OutboxEnvelope, OutboxLock, OutboxWorker}
  alias Hexpm.Repo

  @allowed_options [:category, :group_key, :scope_key, :expires_at]
  @cancel_options [:group_key, :scope_key, :categories]

  def enqueue!(%Swoosh.Email{} = email, opts) do
    email
    |> prepare!(opts)
    |> insert!()
  end

  # Split from insert!/1 so a caller enqueueing inside its own transaction can
  # put the part that raises on a malformed email before the part that issues
  # SQL, and rescue only the first.
  def prepare!(%Swoosh.Email{} = email, opts) do
    attrs = Map.new(opts)
    validate_options!(attrs)
    Map.put(attrs, :email, OutboxEnvelope.dump!(email))
  end

  def insert!(attrs) do
    {:ok, entry} =
      Repo.transaction(fn ->
        OutboxLock.acquire!(attrs[:group_key])

        entry =
          %OutboxEntry{}
          |> OutboxEntry.changeset(attrs)
          |> Repo.insert!(log: false)

        OutboxWorker.enqueue!(entry.id)
        entry
      end)

    entry
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
    from(entry in OutboxEntry,
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
    from(entry in OutboxEntry, where: entry.group_key == ^group_key)
  end

  defp cancel_query({:scope_key, scope_key}) do
    from(entry in OutboxEntry, where: entry.scope_key == ^scope_key)
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

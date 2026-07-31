defmodule Hexpm.Emails.Outbox do
  alias Hexpm.Emails.{OutboxEntry, OutboxEnvelope, OutboxLock, OutboxWorker}
  alias Hexpm.Repo

  @allowed_options [:category, :group_key, :scope_key, :expires_at]

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

  defp validate_options!(attrs) do
    case Map.keys(attrs) -- @allowed_options do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown email outbox options: #{inspect(unknown)}"
    end
  end
end

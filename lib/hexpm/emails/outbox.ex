defmodule Hexpm.Emails.Outbox do
  alias Hexpm.Emails.{OutboxEntry, OutboxEnvelope, OutboxLock, OutboxWorker}
  alias Hexpm.Repo

  @allowed_options [:category, :ordering_key, :scope_key, :expires_at]

  def enqueue!(%Swoosh.Email{} = email, opts) do
    attrs = Map.new(opts)
    validate_options!(attrs)
    attrs = Map.put(attrs, :email, OutboxEnvelope.dump!(email))

    {:ok, entry} =
      Repo.transaction(fn ->
        OutboxLock.acquire!(attrs[:ordering_key])

        entry =
          %OutboxEntry{}
          |> OutboxEntry.changeset(attrs)
          |> Repo.insert!(log: false)

        OutboxWorker.enqueue_if_head!(entry)
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

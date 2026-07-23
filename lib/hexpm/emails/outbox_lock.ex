defmodule Hexpm.Emails.OutboxLock do
  alias Hexpm.Repo

  def acquire!(nil), do: :ok

  def acquire!(ordering_key) do
    Repo.advisory_xact_lock(:email_outbox,
      sub_key: :erlang.phash2(ordering_key, 2_147_483_647)
    )
  end
end

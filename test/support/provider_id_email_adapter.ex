defmodule Hexpm.Emails.ProviderIdAdapter do
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(email, config) do
    if pid = config[:test_pid], do: send(pid, {:email, email})
    {:ok, %{id: config[:message_id] || "provider-message-id"}}
  end
end

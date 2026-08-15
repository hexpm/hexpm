defmodule Hexpm.Emails.FailingAdapter do
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(email, config) do
    if pid = config[:test_pid], do: send(pid, {:delivery_attempt, email})
    {:error, :mail_unavailable}
  end
end

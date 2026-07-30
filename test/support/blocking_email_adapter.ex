defmodule Hexpm.Emails.BlockingAdapter do
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(email, config) do
    send(config[:test_pid], {:delivery_started, email, self()})

    receive do
      :release -> {:ok, %{id: "blocking"}}
    after
      5_000 -> {:error, :never_released}
    end
  end
end

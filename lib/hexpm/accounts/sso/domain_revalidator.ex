defmodule Hexpm.Accounts.SSO.DomainRevalidator do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker]]

  alias Hexpm.Accounts.SSO.DomainVerification

  @doc false
  def timeout_ms, do: :timer.minutes(10)

  @impl Oban.Worker
  def timeout(%Oban.Job{}), do: timeout_ms()

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when map_size(args) == 0 do
    DomainVerification.revalidate_due()
    :ok
  end

  def perform(%Oban.Job{args: args}), do: {:cancel, {:invalid_args, args}}
end

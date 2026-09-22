defmodule Hexpm.Accounts.OrganizationTFAWorker do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Hexpm.Repo.write_mode?(), do: Hexpm.Accounts.OrganizationTFANotifications.sweep()
    :ok
  end
end

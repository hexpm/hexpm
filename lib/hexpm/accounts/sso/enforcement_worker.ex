defmodule Hexpm.Accounts.SSO.EnforcementWorker do
  @moduledoc """
  Warns members before an organization starts requiring SSO, and afterwards
  strips this organization's access from the personal API keys of an
  organization that chose to block them.

  Both halves are predicates over current state rather than actions fired on a
  date, so a tick that never ran leaves nothing half-done and running twice
  changes nothing the second time.
  """

  use Oban.Worker,
    queue: :periodic,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  alias Hexpm.Accounts.SSO.Enforcement

  require Logger

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Hexpm.Repo.write_mode?() do
      warned = Enforcement.warn_pending()
      swept = Enforcement.sweep_personal_keys()

      Logger.info(
        "[task] Warned #{warned} members about pending SSO enforcement and removed organization access from #{swept} personal API keys"
      )
    end

    :ok
  end
end

defmodule Hexpm.Accounts.OrganizationDomains.RecheckWorker do
  @moduledoc """
  Re-checks verified domains so one that has changed hands stops verifying.

  Just-in-time membership admits people on the strength of a verified domain, so
  a record that has been taken down has to take the verification with it rather
  than standing forever on a check made once.
  """

  use Oban.Worker,
    queue: :periodic,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  alias Hexpm.Accounts.OrganizationDomains

  require Logger

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Hexpm.Repo.write_mode?() do
      cleared = OrganizationDomains.recheck_all()
      Logger.info("[task] Cleared #{cleared} organization domains that no longer verify")
    end

    :ok
  end
end

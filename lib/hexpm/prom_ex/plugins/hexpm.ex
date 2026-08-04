defmodule Hexpm.PromEx.Plugins.Hexpm do
  @moduledoc """
  PromEx plugin for hex.pm business metrics, counting the domain events
  emitted from the contexts (see `Hexpm.Repository.Releases` and
  `Hexpm.Accounts.Users`).
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:hexpm_business_event_metrics, [
      counter("hexpm.repository.publish.total",
        event_name: [:hexpm, :repository, :publish],
        description: "Package releases published."
      ),
      counter("hexpm.repository.publish_docs.total",
        event_name: [:hexpm, :repository, :publish_docs],
        description: "Documentation bundles published."
      ),
      counter("hexpm.accounts.user_created.total",
        event_name: [:hexpm, :accounts, :user_created],
        description: "New user accounts created."
      ),
      counter("hexpm.secret_scan.scan.total",
        event_name: [:hexpm, :secret_scan, :scan],
        description: "Release tarballs scanned for credentials."
      ),
      sum("hexpm.secret_scan.scan.findings.total",
        event_name: [:hexpm, :secret_scan, :scan],
        measurement: :findings,
        description: "Credentials found across scanned releases."
      ),
      distribution("hexpm.secret_scan.scan.duration.milliseconds",
        event_name: [:hexpm, :secret_scan, :scan],
        measurement: :duration,
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 500, 1000, 5000, 30_000]],
        description: "Time spent matching a release's files."
      )
    ])
  end
end

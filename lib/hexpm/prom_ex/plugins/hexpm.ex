defmodule Hexpm.PromEx.Plugins.Hexpm do
  @moduledoc """
  PromEx plugin for hex.pm business metrics, counting the domain events
  emitted from the contexts (see `Hexpm.Repository.Releases`,
  `Hexpm.Accounts.Users`, and `Hexpm.TrustedPublishers`).
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
      ),
      counter("hexpm.trusted_publishers.mint.success.total",
        event_name: [:hexpm, :trusted_publishers, :mint, :success],
        description: "Trusted publisher OIDC tokens successfully exchanged for Hex tokens.",
        tags: [:provider],
        tag_values: &__MODULE__.mint_success_tags/1
      ),
      counter("hexpm.trusted_publishers.mint.failure.total",
        event_name: [:hexpm, :trusted_publishers, :mint, :failure],
        description: "Trusted publisher mint attempts that failed.",
        tags: [:reason],
        tag_values: &__MODULE__.mint_failure_tags/1
      )
    ])
  end

  @doc false
  def mint_success_tags(metadata) do
    %{provider: Map.get(metadata, :provider, "unknown")}
  end

  @doc false
  def mint_failure_tags(metadata) do
    %{reason: Map.get(metadata, :reason, "unknown")}
  end
end

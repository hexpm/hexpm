defmodule Hexpm.PromEx.Plugins.Hexpm do
  @moduledoc """
  PromEx plugin for hex.pm business metrics: the domain events emitted from
  the contexts (see `Hexpm.Repository.Releases` and `Hexpm.Accounts.Users`),
  API authentication (`HexpmWeb.AuthHelpers`), registry builds
  (`Hexpm.Repository.RegistryWorker`) and CDN purges (`Hexpm.CDN.PurgeWorker`,
  `Hexpm.CDN.Fastly`), organization billing and deletion
  (`Hexpm.Billing.Report`, `Hexpm.Accounts.OrganizationDeletions`), and the
  number of Erlang nodes this node is connected to.
  """

  use PromEx.Plugin

  @cluster_event [:hexpm, :cluster, :connected_nodes]
  @organizations_event [:hexpm, :organizations, :billing]
  @deletion_steps [:cleared, :scheduled, :reminded, :deleted, :skipped, :failed]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :hexpm_organization_event_metrics,
        [
          sum("hexpm.billing.organization_state_changed.total",
            event_name: [:hexpm, :billing, :organization_state_changed],
            measurement: :count,
            description:
              "Organizations the billing report set active or inactive, by the new state.",
            tags: [:billing_active]
          ),
          sum("hexpm.billing.report_refused.organizations.total",
            event_name: [:hexpm, :billing, :report_refused],
            measurement: :count,
            description: "Organizations a refused billing report would have set inactive at once."
          )
        ] ++
          for step <- @deletion_steps do
            sum("hexpm.organization_deletions.#{step}.total",
              event_name: [:hexpm, :organization_deletions, :run],
              measurement: step,
              description: "Organizations the daily deletion run #{step}."
            )
          end
      ),
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
      ]),
      Event.build(:hexpm_api_event_metrics, [
        counter("hexpm.api.authenticate.total",
          event_name: [:hexpm, :api, :authenticate],
          description: "API requests that carried an Authorization header, by scheme and result.",
          tags: [:scheme, :result]
        )
      ]),
      Event.build(:hexpm_registry_builder_event_metrics, [
        counter("hexpm.registry_builder.build.total",
          event_name: [:hexpm, :registry_builder, :build, :stop],
          description: "Registry builds that finished, by type and result.",
          tags: [:type, :result]
        ),
        distribution("hexpm.registry_builder.build.duration.milliseconds",
          event_name: [:hexpm, :registry_builder, :build, :stop],
          measurement: :duration,
          description: "How long a registry build took, lock wait included.",
          reporter_options: [
            buckets: [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000, 60_000, 300_000]
          ],
          tags: [:type],
          unit: {:native, :millisecond}
        ),
        counter("hexpm.registry_builder.build.exception.total",
          event_name: [:hexpm, :registry_builder, :build, :exception],
          description: "Registry builds that raised.",
          tags: [:type]
        )
      ]),
      Event.build(:hexpm_sentry_event_metrics, [
        counter("hexpm.sentry.filtered.total",
          event_name: [:hexpm, :sentry, :filtered],
          description:
            "Sentry events dropped by the before_send filter and counted here instead, by class.",
          tags: [:class]
        )
      ]),
      Event.build(:hexpm_cdn_event_metrics, [
        counter("hexpm.cdn.purge_request.total",
          event_name: [:hexpm, :cdn, :purge_request, :stop],
          description: "Purge requests sent to Fastly, by service and response status.",
          tags: [:service, :status]
        ),
        distribution("hexpm.cdn.purge_request.duration.milliseconds",
          event_name: [:hexpm, :cdn, :purge_request, :stop],
          measurement: :duration,
          description: "How long a purge request to Fastly took.",
          reporter_options: [buckets: [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]],
          tags: [:service],
          unit: {:native, :millisecond}
        ),
        counter("hexpm.cdn.verify.total",
          event_name: [:hexpm, :cdn, :verify, :stop],
          description:
            "Post-purge checks of an object, by POP (nearest is the direct fetch) and result.",
          tags: [:pop, :result]
        ),
        counter("hexpm.cdn.purge.total",
          event_name: [:hexpm, :cdn, :purge, :stop],
          description:
            "Purge jobs that finished, by service, result and the verification rounds it took.",
          tags: [:service, :result, :rounds]
        ),
        distribution("hexpm.cdn.purge.duration.milliseconds",
          event_name: [:hexpm, :cdn, :purge, :stop],
          measurement: :duration,
          description: "How long a purge job took from first purge to verified.",
          reporter_options: [
            buckets: [2_500, 5_000, 7_500, 10_000, 15_000, 30_000, 60_000, 120_000, 300_000]
          ],
          tags: [:service, :result],
          unit: {:native, :millisecond}
        ),
        sum("hexpm.cdn.purge.absorbed.total",
          event_name: [:hexpm, :cdn, :purge, :stop],
          measurement: fn _measurements, metadata -> metadata.absorbed end,
          description: "Queued purge jobs merged into a running one.",
          tags: [:service]
        ),
        counter("hexpm.cdn.purge.exception.total",
          event_name: [:hexpm, :cdn, :purge, :exception],
          description: "Purge jobs that raised, verification failures included.",
          tags: [:service]
        )
      ])
    ]
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      Polling.build(
        :hexpm_cluster_polling_metrics,
        poll_rate,
        {__MODULE__, :execute_cluster_metrics, []},
        [
          last_value("hexpm.cluster.connected_nodes",
            event_name: @cluster_event,
            measurement: :count,
            description: "Erlang nodes this node is connected to, the length of Node.list/0."
          )
        ]
      ),
      # A count over the organizations table, so once a minute rather than at
      # the cluster gauge's rate.
      Polling.build(
        :hexpm_organization_polling_metrics,
        :timer.minutes(1),
        {__MODULE__, :execute_organization_metrics, []},
        for state <- [:active, :inactive, :scheduled] do
          last_value("hexpm.organizations.#{state}",
            event_name: @organizations_event,
            measurement: state,
            description:
              "Organizations #{organization_state_description(state)}, the public one excluded."
          )
        end
      )
    ]
  end

  defp organization_state_description(:active), do: "with active, trialing or comped billing"
  defp organization_state_description(:inactive), do: "without billing"
  defp organization_state_description(:scheduled), do: "scheduled for deletion"

  # telemetry_poller stops calling a measurement that raises or exits, for
  # good. The first poll runs as the node boots, before the repo is up, and a
  # database error can come at any time, so any failure skips this minute's
  # reading instead.
  @doc false
  def execute_organization_metrics do
    :telemetry.execute(
      @organizations_event,
      Hexpm.Accounts.OrganizationDeletions.state_counts(),
      %{}
    )
  rescue
    exception -> skip_organization_metrics(Exception.message(exception))
  catch
    :exit, reason -> skip_organization_metrics(inspect(reason))
  end

  defp skip_organization_metrics(reason) do
    require Logger
    Logger.warning("organization metrics skipped: #{reason}")
    :ok
  end

  @doc false
  def execute_cluster_metrics do
    :telemetry.execute(@cluster_event, %{count: length(Node.list())}, %{})
  end
end

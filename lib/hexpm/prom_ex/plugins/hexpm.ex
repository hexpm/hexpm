defmodule Hexpm.PromEx.Plugins.Hexpm do
  @moduledoc """
  PromEx plugin for hex.pm business metrics: the domain events emitted from
  the contexts (see `Hexpm.Repository.Releases` and `Hexpm.Accounts.Users`),
  API authentication (`HexpmWeb.AuthHelpers`), registry builds
  (`Hexpm.Repository.RegistryWorker`) and CDN purges (`Hexpm.CDN.PurgeWorker`,
  `Hexpm.CDN.Fastly`), and the number of Erlang nodes this node is connected to.
  """

  use PromEx.Plugin

  @cluster_event [:hexpm, :cluster, :connected_nodes]

  @impl true
  def event_metrics(_opts) do
    [
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
    )
  end

  @doc false
  def execute_cluster_metrics do
    :telemetry.execute(@cluster_event, %{count: length(Node.list())}, %{})
  end
end

defmodule Hexpm.PromEx.Plugins.Hexpm do
  @moduledoc """
  PromEx plugin for hex.pm business metrics: the domain events emitted from
  the contexts (see `Hexpm.Repository.Releases`, `Hexpm.Accounts.Users` and
  `Hexpm.WorkloadIdentities`), API authentication (`HexpmWeb.AuthHelpers`),
  registry builds (`Hexpm.Repository.RegistryWorker`) and CDN purges
  (`Hexpm.CDN.PurgeWorker`, `Hexpm.CDN.Fastly`), organization billing and
  deletion (`Hexpm.Billing.Report`, `Hexpm.Accounts.OrganizationDeletions`), and
  the number of Erlang nodes this node is connected to.

  A counter series is created by its first event, and Prometheus' `increase()`
  needs two samples, so it never counts that first event. The counters are
  sums of each event's `:count` measurement, 1 when absent, and
  `initialize_counters/0` creates every series with a bounded set of labels at
  zero when the application starts. Registry builds and purge jobs are counted
  on a `:done` event of their own, since a zero on `:stop` would also reach
  the duration histogram. The secret scan counters share their event with the
  scan duration histogram, so they start with the first scan.
  """

  use PromEx.Plugin

  alias Hexpm.WorkloadIdentities.Provider

  @cluster_event [:hexpm, :cluster, :connected_nodes]
  @organizations_event [:hexpm, :organizations, :billing]
  @deletion_steps [:cleared, :scheduled, :reminded, :deleted, :skipped, :failed]

  @authenticate_results [
    basic: [:ok, :basic_auth_disabled, :password, :invalid],
    bearer: [:ok, :key],
    key: [:ok, :key, :revoked_key]
  ]
  @registry_build_types [:package, :package_delete, :repository, :full]
  @registry_build_results [:ok, :discard, :snooze]
  @sentry_filtered_classes [
    :pool_timeout,
    :db_connect,
    :db_disconnect,
    :too_many_connections,
    :query_canceled,
    :client_transport,
    :response_not_sent,
    :db_connection_exit
  ]
  @cdn_services [:fastly_hexrepo, :fastly_hexdocs, :fastly_hexdocs_private]
  @cdn_verify_results [:ok, :stale, :error]

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
        sum("hexpm.repository.publish.total",
          event_name: [:hexpm, :repository, :publish],
          measurement: &__MODULE__.count/1,
          description: "Package releases published."
        ),
        sum("hexpm.repository.publish_docs.total",
          event_name: [:hexpm, :repository, :publish_docs],
          measurement: &__MODULE__.count/1,
          description: "Documentation bundles published."
        ),
        sum("hexpm.accounts.user_created.total",
          event_name: [:hexpm, :accounts, :user_created],
          measurement: &__MODULE__.count/1,
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
        sum("hexpm.workload_identity.mint.success.total",
          event_name: [:hexpm, :workload_identity, :mint, :success],
          measurement: &__MODULE__.count/1,
          description: "Workload identity OIDC tokens successfully exchanged for Hex tokens.",
          tags: [:provider],
          tag_values: &__MODULE__.mint_success_tags/1
        ),
        counter("hexpm.workload_identity.mint.failure.total",
          event_name: [:hexpm, :workload_identity, :mint, :failure],
          description: "Workload identity token exchanges that failed.",
          tags: [:reason],
          tag_values: &__MODULE__.mint_failure_tags/1
        )
      ]),
      Event.build(:hexpm_api_event_metrics, [
        sum("hexpm.api.authenticate.total",
          event_name: [:hexpm, :api, :authenticate],
          measurement: &__MODULE__.count/1,
          description: "API requests that carried an Authorization header, by scheme and result.",
          tags: [:scheme, :result]
        )
      ]),
      Event.build(:hexpm_registry_builder_event_metrics, [
        sum("hexpm.registry_builder.build.total",
          event_name: [:hexpm, :registry_builder, :build, :done],
          measurement: &__MODULE__.count/1,
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
        sum("hexpm.registry_builder.build.exception.total",
          event_name: [:hexpm, :registry_builder, :build, :exception],
          measurement: &__MODULE__.count/1,
          description: "Registry builds that raised.",
          tags: [:type]
        )
      ]),
      Event.build(:hexpm_sentry_event_metrics, [
        sum("hexpm.sentry.filtered.total",
          event_name: [:hexpm, :sentry, :filtered],
          measurement: &__MODULE__.count/1,
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
          reporter_options: [
            buckets: [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
          ],
          tags: [:service],
          unit: {:native, :millisecond}
        ),
        sum("hexpm.cdn.verify.total",
          event_name: [:hexpm, :cdn, :verify, :stop],
          measurement: &__MODULE__.count/1,
          description:
            "Post-purge checks of an object, by POP (nearest is the direct fetch) and result.",
          tags: [:pop, :result]
        ),
        sum("hexpm.cdn.purge.total",
          event_name: [:hexpm, :cdn, :purge, :done],
          measurement: &__MODULE__.count/1,
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
          event_name: [:hexpm, :cdn, :purge, :absorb],
          measurement: :count,
          description: "Queued purge jobs merged into a running one.",
          tags: [:service]
        ),
        sum("hexpm.cdn.purge.exception.total",
          event_name: [:hexpm, :cdn, :purge, :exception],
          measurement: &__MODULE__.count/1,
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
  defp organization_state_description(:scheduled), do: "scheduled for data deletion"

  @doc false
  def count(measurements), do: Map.get(measurements, :count, 1)

  @doc """
  Reports a zero for every counter series with a bounded set of labels, so the
  first real event is an increase Prometheus can see. Called by
  `Hexpm.PromEx.initialize_counters/0`.
  """
  def initialize_counters() do
    for event <- [
          [:hexpm, :repository, :publish],
          [:hexpm, :repository, :publish_docs],
          [:hexpm, :accounts, :user_created],
          [:hexpm, :billing, :report_refused]
        ] do
      :telemetry.execute(event, %{count: 0}, %{})
    end

    for billing_active <- [true, false] do
      :telemetry.execute([:hexpm, :billing, :organization_state_changed], %{count: 0}, %{
        billing_active: billing_active
      })
    end

    :telemetry.execute(
      [:hexpm, :organization_deletions, :run],
      Map.new(@deletion_steps, &{&1, 0}),
      %{}
    )

    for provider <- Provider.names() do
      :telemetry.execute([:hexpm, :workload_identity, :mint, :success], %{count: 0}, %{
        provider: provider
      })
    end

    for {scheme, results} <- @authenticate_results, result <- results do
      :telemetry.execute([:hexpm, :api, :authenticate], %{count: 0}, %{
        scheme: scheme,
        result: result
      })
    end

    for type <- @registry_build_types do
      for result <- @registry_build_results do
        :telemetry.execute([:hexpm, :registry_builder, :build, :done], %{count: 0}, %{
          type: type,
          result: result
        })
      end

      :telemetry.execute([:hexpm, :registry_builder, :build, :exception], %{count: 0}, %{
        type: type
      })
    end

    for class <- @sentry_filtered_classes do
      :telemetry.execute([:hexpm, :sentry, :filtered], %{count: 0}, %{class: class})
    end

    pops = [:nearest | Application.fetch_env!(:hexpm, :fastly_probe_pops)]

    for pop <- pops, result <- @cdn_verify_results do
      :telemetry.execute([:hexpm, :cdn, :verify, :stop], %{count: 0}, %{pop: pop, result: result})
    end

    max_rounds = Application.fetch_env!(:hexpm, :purge_verify_rounds)
    purges = [{:error, 0} | Enum.map(0..max_rounds, &{:ok, &1})]

    for service <- @cdn_services do
      for {result, rounds} <- purges do
        :telemetry.execute([:hexpm, :cdn, :purge, :done], %{count: 0}, %{
          service: service,
          result: result,
          rounds: rounds
        })
      end

      :telemetry.execute([:hexpm, :cdn, :purge, :absorb], %{count: 0}, %{service: service})

      :telemetry.execute([:hexpm, :cdn, :purge, :exception], %{count: 0}, %{service: service})
    end

    :ok
  end

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

  @doc false
  def mint_success_tags(metadata) do
    %{provider: Map.get(metadata, :provider, "unknown")}
  end

  @doc false
  def mint_failure_tags(metadata) do
    %{reason: Map.get(metadata, :reason, "unknown")}
  end
end

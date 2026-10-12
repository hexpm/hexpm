defmodule Hexpm.PromEx.Plugins.DbConnection do
  @moduledoc """
  PromEx plugin for the database connection pool: refused checkouts and
  connection churn.

  `[:db_connection, :connection_error]` fires where the pool gives up on a
  checkout. The reason is `:queue_timeout` when the caller waited out the queue
  and `:error` when there was no connection to wait for. Connects and
  disconnects come from the `DBConnection.TelemetryListener` the repo is
  started with. Every event's `:count` is 1, and the counters are sums of it,
  so `initialize_counters/0` can create them at zero before the repo connects.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    metric_prefix =
      Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :db_connection))

    Event.build(:hexpm_db_connection_event_metrics, [
      sum(
        metric_prefix ++ [:connection_error, :total],
        event_name: [:db_connection, :connection_error],
        measurement: :count,
        description: "Connection checkouts the pool refused, by reason.",
        tags: [:reason],
        tag_values: &__MODULE__.error_tags/1
      ),
      sum(
        metric_prefix ++ [:connected, :total],
        event_name: [:db_connection, :connected],
        measurement: :count,
        description: "Database connections established."
      ),
      sum(
        metric_prefix ++ [:disconnected, :total],
        event_name: [:db_connection, :disconnected],
        measurement: :count,
        description: "Database connections lost or closed."
      )
    ])
  end

  def error_tags(%{error: %DBConnection.ConnectionError{reason: reason}}), do: %{reason: reason}
  def error_tags(_metadata), do: %{reason: :unknown}

  @doc """
  Reports a zero for each counter, and for each reason a checkout is refused
  with, so the first real event is an increase Prometheus can see. Called by
  `Hexpm.PromEx.initialize_counters/0`.
  """
  def initialize_counters() do
    for reason <- [:error, :queue_timeout] do
      :telemetry.execute([:db_connection, :connection_error], %{count: 0}, %{
        error: %DBConnection.ConnectionError{reason: reason}
      })
    end

    :telemetry.execute([:db_connection, :connected], %{count: 0}, %{})
    :telemetry.execute([:db_connection, :disconnected], %{count: 0}, %{})
    :ok
  end
end

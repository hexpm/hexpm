defmodule Hexpm.PromEx.Plugins.DbConnection do
  @moduledoc """
  PromEx plugin for the database connection pool: refused checkouts and
  connection churn.

  `[:db_connection, :connection_error]` fires where the pool gives up on a
  checkout. The reason is `:queue_timeout` when the caller waited out the queue
  and `:error` when there was no connection to wait for. Connects and
  disconnects come from the `DBConnection.TelemetryListener` the repo is
  started with.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    metric_prefix =
      Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :db_connection))

    Event.build(:hexpm_db_connection_event_metrics, [
      counter(
        metric_prefix ++ [:connection_error, :total],
        event_name: [:db_connection, :connection_error],
        description: "Connection checkouts the pool refused, by reason.",
        tags: [:reason],
        tag_values: &__MODULE__.error_tags/1
      ),
      counter(
        metric_prefix ++ [:connected, :total],
        event_name: [:db_connection, :connected],
        description: "Database connections established."
      ),
      counter(
        metric_prefix ++ [:disconnected, :total],
        event_name: [:db_connection, :disconnected],
        description: "Database connections lost or closed."
      )
    ])
  end

  def error_tags(%{error: %DBConnection.ConnectionError{reason: reason}}), do: %{reason: reason}
  def error_tags(_metadata), do: %{reason: :unknown}
end

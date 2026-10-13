defmodule Hexpm.PromEx.Plugins.Email do
  @moduledoc """
  PromEx plugin for mail handed to Swoosh, from the outbox worker and from
  direct sends alike.

  Every builder in `Hexpm.Emails` tags its mail with a type, so the series are
  bounded by the number of builders. The outcome is `ok`, the provider's HTTP
  status when it refused the mail, or `error` when there was no response.

  The counters are sums of the `:count` of the events `Hexpm.Emails.Telemetry`
  emits for each of Swoosh's, so `initialize_counters/0` can create every
  type's series at zero without the zero reaching the duration histogram,
  which reads Swoosh's event.
  """

  use PromEx.Plugin

  @deliver_event [:hexpm, :email, :deliver, :done]
  @exception_event [:hexpm, :email, :deliver, :raised]

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :email))

    Event.build(:hexpm_email_event_metrics, [
      sum(
        metric_prefix ++ [:deliver, :total],
        event_name: @deliver_event,
        measurement: :count,
        description: "Mail handed to the provider, by email type and outcome.",
        tags: [:type, :outcome]
      ),
      distribution(
        metric_prefix ++ [:deliver, :duration, :milliseconds],
        event_name: [:swoosh, :deliver, :stop],
        measurement: :duration,
        description: "How long handing one mail to the provider took.",
        reporter_options: [buckets: [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000]],
        tags: [:type],
        tag_values: &__MODULE__.type_tags/1,
        unit: {:native, :millisecond}
      ),
      sum(
        metric_prefix ++ [:deliver, :exception, :total],
        event_name: @exception_event,
        measurement: :count,
        description: "Deliveries that raised.",
        tags: [:type]
      )
    ])
  end

  @doc """
  Reports one delivery Swoosh finished, from its `[:swoosh, :deliver, :stop]`
  metadata.
  """
  def delivered(metadata) do
    :telemetry.execute(@deliver_event, %{count: 1}, %{
      type: type(metadata),
      outcome: outcome(metadata)
    })
  end

  @doc """
  Reports one delivery that raised, from its `[:swoosh, :deliver, :exception]`
  metadata.
  """
  def raised(metadata) do
    :telemetry.execute(@exception_event, %{count: 1}, %{type: type(metadata)})
  end

  @doc """
  Reports a zero for every email type's deliveries that succeeded or failed
  without a response, and for its deliveries that raised, so the first real
  event is an increase Prometheus can see. Called by
  `Hexpm.PromEx.initialize_counters/0`.
  """
  def initialize_counters() do
    for type <- Hexpm.Emails.types() do
      for outcome <- ["ok", "error"] do
        :telemetry.execute(@deliver_event, %{count: 0}, %{type: type, outcome: outcome})
      end

      :telemetry.execute(@exception_event, %{count: 0}, %{type: type})
    end

    :ok
  end

  @doc false
  def type_tags(metadata), do: %{type: type(metadata)}

  @doc false
  def type(%{email: %Swoosh.Email{private: %{type: type}}}) when is_binary(type), do: type
  def type(_metadata), do: "untyped"

  @doc false
  def outcome(%{error: {status, _body}}) when is_integer(status), do: Integer.to_string(status)
  def outcome(%{error: _error}), do: "error"
  def outcome(_metadata), do: "ok"
end

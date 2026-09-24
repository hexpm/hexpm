defmodule Hexpm.PromEx.Plugins.Email do
  @moduledoc """
  PromEx plugin for mail handed to Swoosh, from the outbox worker and from
  direct sends alike.

  Every builder in `Hexpm.Emails` tags its mail with a type, so the series are
  bounded by the number of builders. The outcome is `ok`, the provider's HTTP
  status when it refused the mail, or `error` when there was no response.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :email))

    Event.build(:hexpm_email_event_metrics, [
      counter(
        metric_prefix ++ [:deliver, :total],
        event_name: [:swoosh, :deliver, :stop],
        description: "Mail handed to the provider, by email type and outcome.",
        tags: [:type, :outcome],
        tag_values: &__MODULE__.deliver_tags/1
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
      counter(
        metric_prefix ++ [:deliver, :exception, :total],
        event_name: [:swoosh, :deliver, :exception],
        description: "Deliveries that raised.",
        tags: [:type],
        tag_values: &__MODULE__.type_tags/1
      )
    ])
  end

  @doc false
  def deliver_tags(metadata) do
    %{type: type(metadata), outcome: outcome(metadata)}
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

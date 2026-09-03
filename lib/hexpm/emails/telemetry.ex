defmodule Hexpm.Emails.Telemetry do
  @moduledoc """
  Logs one line per delivery attempt, so the mail we handed to the provider
  can be matched against what the provider reports.
  """

  require Logger

  alias Hexpm.PromEx.Plugins.Email, as: Metrics

  @events [[:swoosh, :deliver, :stop], [:swoosh, :deliver, :exception]]

  def attach do
    :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)
  end

  @doc false
  def handle_event([:swoosh, :deliver, :stop], measurements, metadata, _config) do
    case metadata do
      %{error: error} ->
        log(:warning, metadata, measurements, error: inspect(error, printable_limit: 200))

      %{result: result} ->
        log(:info, metadata, measurements, message_id: message_id(result))
    end
  end

  def handle_event([:swoosh, :deliver, :exception], measurements, metadata, _config) do
    log(:warning, metadata, measurements,
      outcome: "exception",
      kind: metadata[:kind],
      reason: inspect(metadata[:reason], printable_limit: 200)
    )
  end

  defp log(level, metadata, %{duration: duration}, extra) do
    fields =
      [type: Metrics.type(metadata), outcome: Metrics.outcome(metadata)]
      |> Keyword.merge(extra)
      |> Keyword.put(:duration_us, System.convert_time_unit(duration, :native, :microsecond))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    Logger.log(level, "[email] #{fields[:type]} #{fields[:outcome]}", fields)
  end

  defp message_id(%{id: id}) when is_binary(id), do: id
  defp message_id(_result), do: nil
end

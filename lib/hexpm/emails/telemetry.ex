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
        Logger.warning(line(metadata, measurements, error: inspect(error, printable_limit: 200)))

      %{result: result} ->
        Logger.info(line(metadata, measurements, message_id: message_id(result)))
    end
  end

  def handle_event([:swoosh, :deliver, :exception], measurements, metadata, _config) do
    Logger.warning(
      line(metadata, measurements,
        outcome: "exception",
        kind: metadata[:kind],
        reason: inspect(metadata[:reason], printable_limit: 200)
      )
    )
  end

  # The outbox worker puts its entry on the process's Logger metadata; the
  # formatter prints only request_id, so it goes into the message here.
  defp line(metadata, %{duration: duration}, extra) do
    logger_metadata = Logger.metadata()

    fields =
      [
        type: Metrics.type(metadata),
        outcome: Metrics.outcome(metadata),
        outbox_entry_id: logger_metadata[:outbox_entry_id],
        category: logger_metadata[:outbox_category]
      ]
      |> Keyword.merge(extra)
      |> Kernel.++(duration: "#{System.convert_time_unit(duration, :native, :millisecond)}ms")
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{value}" end)

    "[email] " <> fields
  end

  defp message_id(%{id: id}) when is_binary(id), do: id
  defp message_id(_result), do: nil
end

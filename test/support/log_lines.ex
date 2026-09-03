defmodule Hexpm.LogLines do
  @moduledoc """
  A `:logger` handler, attached for the test run, that sends every line a
  process logs back to that process as `{Hexpm.LogLines, level, fields}`. The
  fields are what production writes: the message map's keys, or `:message`
  for a plain message, and the process metadata that reaches the line.
  """

  def log(%{level: level, msg: msg, meta: %{pid: pid} = meta}, _config) do
    send(pid, {__MODULE__, level, fields(msg, meta)})
  rescue
    _ -> :ok
  end

  def log(_event, _config), do: :ok

  defp fields({:report, report}, meta), do: Map.merge(metadata(meta), Map.new(report))

  defp fields({:string, chardata}, meta),
    do: Map.put(metadata(meta), :message, IO.chardata_to_string(chardata))

  defp fields({format, args}, meta),
    do: Map.put(metadata(meta), :message, format |> :io_lib.format(args) |> to_string())

  defp metadata(meta), do: Map.take(meta, Application.fetch_env!(:hexpm, :log_metadata))
end

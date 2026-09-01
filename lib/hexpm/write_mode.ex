defmodule Hexpm.WriteMode do
  @topic "write_mode"

  def enabled?() do
    mode() == :read_only
  end

  def mode() do
    normalize(Application.get_env(:hexpm, :read_only_mode, false))
  end

  defp normalize(false), do: :write
  defp normalize(true), do: :read_only
  defp normalize(mode), do: mode

  def configure!(mode) when mode in [false, :hold, :hold_all, true] do
    Hexpm.WriteModePubSub.configure(mode)
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(Hexpm.PubSub, @topic)
  end

  def broadcast_from!(pid, mode) do
    Phoenix.PubSub.broadcast_from!(Hexpm.PubSub, pid, @topic, {:write_mode, mode})
  end

  @doc """
  Parks the calling process while the mode is `:hold` or `:hold_all`.

  Returns `:ok` when writes may proceed, `:unavailable` when the mode is or
  becomes `:read_only`, and `:timeout` when the deadline passes first. Only
  masks pauses shorter than the caller's tolerance for latency; anything
  longer must fall back to rejecting the request.
  """
  def await_write(timeout) do
    await_mode(:write, timeout)
  end

  @doc """
  Parks the calling process while the mode is `:hold_all`.

  Reads flow in every other mode; `:hold_all` exists so the seconds around a
  connection pool restart hold the whole request instead of letting in-flight
  queries die with connection errors.
  """
  def await_read(timeout) do
    await_mode(:read, timeout)
  end

  defp await_mode(kind, timeout) do
    case classify(kind, mode()) do
      :park ->
        :ok = Phoenix.PubSub.subscribe(Hexpm.PubSub, @topic)

        try do
          await(kind, System.monotonic_time(:millisecond) + timeout)
        after
          Phoenix.PubSub.unsubscribe(Hexpm.PubSub, @topic)
        end

      result ->
        result
    end
  end

  defp await(kind, deadline) do
    # Re-read after subscribing: a release broadcast between the first mode
    # check and the subscribe would otherwise never reach this process.
    case classify(kind, mode()) do
      :park ->
        wait = deadline - System.monotonic_time(:millisecond)

        if wait <= 0 do
          :timeout
        else
          receive do
            {:write_mode, value} ->
              case classify(kind, normalize(value)) do
                :park -> await(kind, deadline)
                result -> result
              end
          after
            wait -> :timeout
          end
        end

      result ->
        result
    end
  end

  defp classify(:write, :write), do: :ok
  defp classify(:write, :read_only), do: :unavailable
  defp classify(:write, hold) when hold in [:hold, :hold_all], do: :park
  defp classify(:read, :hold_all), do: :park
  defp classify(:read, _mode), do: :ok
end

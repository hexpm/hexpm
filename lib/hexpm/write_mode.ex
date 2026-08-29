defmodule Hexpm.WriteMode do
  @topic "write_mode"

  def enabled?() do
    mode() == :read_only
  end

  def mode() do
    case Application.get_env(:hexpm, :read_only_mode, false) do
      false -> :write
      :hold -> :hold
      true -> :read_only
    end
  end

  def configure!(mode) when mode in [false, :hold, true] do
    Hexpm.WriteModePubSub.configure(mode)
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(Hexpm.PubSub, @topic)
  end

  def broadcast_from!(pid, mode) do
    Phoenix.PubSub.broadcast_from!(Hexpm.PubSub, pid, @topic, {:write_mode, mode})
  end

  @doc """
  Parks the calling process while the mode is `:hold`.

  Returns `:ok` when writes may proceed, `:unavailable` when the mode is or
  becomes `:read_only`, and `:timeout` when the deadline passes first. Only
  masks pauses shorter than the caller's tolerance for latency; anything
  longer must fall back to rejecting the request.
  """
  def await_write(timeout) do
    case mode() do
      :write ->
        :ok

      :read_only ->
        :unavailable

      :hold ->
        :ok = Phoenix.PubSub.subscribe(Hexpm.PubSub, @topic)

        try do
          await(System.monotonic_time(:millisecond) + timeout)
        after
          Phoenix.PubSub.unsubscribe(Hexpm.PubSub, @topic)
        end
    end
  end

  defp await(deadline) do
    # Re-read after subscribing: a release broadcast between the first mode
    # check and the subscribe would otherwise never reach this process.
    case mode() do
      :write ->
        :ok

      :read_only ->
        :unavailable

      :hold ->
        wait = deadline - System.monotonic_time(:millisecond)

        if wait <= 0 do
          :timeout
        else
          receive do
            {:write_mode, false} -> :ok
            {:write_mode, true} -> :unavailable
            {:write_mode, :hold} -> await(deadline)
          after
            wait -> :timeout
          end
        end
    end
  end
end

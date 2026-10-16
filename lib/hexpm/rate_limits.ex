defmodule Hexpm.RateLimits do
  @moduledoc """
  Rate limit counters in the database, which every pod shares and a deploy
  doesn't reset. `HexpmWeb.Plugs.Attack` uses this module as a throttle's
  storage in place of `PlugAttack.Storage.Ets`. Expired counters are deleted
  by `Hexpm.PurgeExpiredRecords`.
  """

  use Hexpm.Context

  alias Hexpm.RateLimit

  @doc """
  Adds `increment` to the counter for `key` and returns the new count. A new
  counter expires at `expires_at`, in unix milliseconds. An increment of 0
  reads the count without writing.
  """
  def increment(_opts, key, 0, _expires_at) do
    Repo.one(from(r in RateLimit, where: r.key == ^encode(key), select: r.count)) || 0
  end

  def increment(_opts, key, increment, expires_at) do
    counter = %{
      key: encode(key),
      count: increment,
      expires_at: DateTime.from_unix!(expires_at * 1_000, :microsecond)
    }

    {1, [%RateLimit{count: count}]} =
      Repo.insert_all(RateLimit, [counter],
        on_conflict: [inc: [count: increment]],
        conflict_target: [:key],
        returning: [:count]
      )

    count
  end

  defp encode({:throttle, {name, subject}, bucket}), do: "#{name}:#{subject(subject)}:#{bucket}"
  defp encode({name, subject}), do: "#{name}:#{subject(subject)}"

  defp subject(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> List.to_string()
  defp subject(id), do: to_string(id)
end

defmodule Hexpm.Store.Memory do
  # Only used during testing. ETS-backed store with per-process isolation
  # to allow async tests without shared filesystem conflicts.

  @behaviour Hexpm.Store.Behaviour

  @table __MODULE__
  @ownership __MODULE__.Ownership
  @key :store

  def start() do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, _} = NimbleOwnership.start_link(name: @ownership)
    :ok
  end

  def checkout() do
    NimbleOwnership.get_and_update(@ownership, self(), @key, fn _ -> {:ok, true} end)
  end

  def list(bucket, prefix) do
    owner = owner_pid()

    :ets.match_object(@table, {{owner, bucket, :_}, :_})
    |> Enum.flat_map(fn {{_, _, key}, _value} ->
      if String.starts_with?(key, prefix) do
        [key]
      else
        []
      end
    end)
  end

  def get(bucket, key, _opts) do
    owner = owner_pid()

    case :ets.lookup(@table, {owner, bucket, key}) do
      [{_, value}] -> value
      [] -> nil
    end
  end

  def put(bucket, key, body, _opts) do
    owner = owner_pid()
    :ets.insert(@table, {{owner, bucket, key}, body})
  end

  def delete(bucket, key) do
    owner = owner_pid()
    :ets.delete(@table, {owner, bucket, key})
  end

  def delete_many(bucket, keys) do
    Enum.each(keys, &delete(bucket, &1))
  end

  defp owner_pid() do
    callers = [self() | Process.get(:"$callers") || []]

    case NimbleOwnership.fetch_owner(@ownership, callers, @key) do
      {tag, owner} when tag in [:ok, :shared_owner] -> owner
      :error -> self()
    end
  end
end

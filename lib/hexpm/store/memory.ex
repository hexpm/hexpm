defmodule Hexpm.Store.Memory do
  # Only used during testing. ETS-backed store with per-process isolation
  # to allow async tests without shared filesystem conflicts.

  @behaviour Hexpm.Store.Behaviour

  @table __MODULE__
  @chunk_size 65_536
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

  def list_objects(bucket, prefix) do
    owner = owner_pid()

    :ets.match_object(@table, {{owner, bucket, :_}, :_, :_})
    |> Enum.flat_map(fn {{_, _, key}, _value, last_modified} ->
      if String.starts_with?(key, prefix) do
        [%{key: key, last_modified: last_modified}]
      else
        []
      end
    end)
  end

  def get(bucket, key, _opts) do
    owner = owner_pid()

    case :ets.lookup(@table, {owner, bucket, key}) do
      [{_, value, _last_modified}] -> value
      [] -> nil
    end
  end

  def size(bucket, key) do
    case get(bucket, key, []) do
      nil -> nil
      body -> byte_size(body)
    end
  end

  def stream(bucket, key) do
    case get(bucket, key, []) do
      nil ->
        nil

      body ->
        Stream.unfold(body, fn
          "" -> nil
          <<chunk::binary-size(@chunk_size), rest::binary>> -> {chunk, rest}
          chunk -> {chunk, ""}
        end)
    end
  end

  def get_to_file(bucket, key, destination, opts) do
    case get(bucket, key, opts) do
      nil -> nil
      body -> File.write!(destination, body)
    end
  end

  def put(bucket, key, body, _opts) do
    owner = owner_pid()
    written_at = Process.get({__MODULE__, :written_at}) || DateTime.utc_now()
    :ets.insert(@table, {{owner, bucket, key}, body, written_at})
    {:ok, %{etag: ~s("#{Base.encode16(:crypto.hash(:md5, body), case: :lower)}")}}
  end

  @doc """
  Dates every object this process writes from here on at `datetime`, so a test
  can put an object that the store reports as older than it is.
  """
  def written_at(datetime) do
    Process.put({__MODULE__, :written_at}, datetime)
    :ok
  end

  def put_file(bucket, key, path, opts) do
    body = File.read!(path)
    put(bucket, key, body, opts)
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

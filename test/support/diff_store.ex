defmodule Hexpm.Diff.TestStore do
  @behaviour Hexpm.Store.Behaviour

  defdelegate list(bucket, prefix), to: Hexpm.Store.Memory
  defdelegate size(bucket, key), to: Hexpm.Store.Memory
  defdelegate get_to_file(bucket, key, destination, opts), to: Hexpm.Store.Memory
  defdelegate put_file(bucket, key, path, opts), to: Hexpm.Store.Memory
  defdelegate delete(bucket, key), to: Hexpm.Store.Memory
  defdelegate delete_many(bucket, keys), to: Hexpm.Store.Memory

  def get(bucket, key, opts) do
    case Application.get_env(:hexpm, :diff_test_store_get) do
      :raise -> raise "storage unavailable"
      :throw -> throw(:unavailable)
      nil -> Hexpm.Store.Memory.get(bucket, key, opts)
    end
  end

  def put(bucket, key, body, opts) do
    case Application.get_env(:hexpm, :diff_test_store_put) do
      {marker, result} ->
        if String.contains?(key, marker),
          do: result,
          else: Hexpm.Store.Memory.put(bucket, key, body, opts)

      nil ->
        Hexpm.Store.Memory.put(bucket, key, body, opts)
    end
  end
end

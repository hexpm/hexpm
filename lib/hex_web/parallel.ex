defmodule HexWeb.Parallel do
  use GenServer
  require Logger

  @timeout 60 * 1000
  @parallel 10

  def each(fun, args, opts \\ [])

  def each(_fun, [], _opts), do: []
  def each(fun, args, opts) do
    opts = default_opts(opts)
    num_args = length(args)
    HexWeb.Parallel.ETS.each(fun, num_args, args, opts)
  end

  def each!(fun, args, opts \\ [])

  def each!(fun, args, opts) do
    results = each(fun, args, opts)
    Enum.map(results, fn
      {:ok, value} ->
        value
      {:error, _} ->
        raise "Parallel tasks failed"
    end)
  end

  def reduce(fun, args, acc, reducer, opts \\ [])

  def reduce(_fun, [], acc, _reducer, _opts), do: acc
  def reduce(fun, args, acc, reducer, opts) do
    opts = default_opts(opts)
    HexWeb.Parallel.Process.reduce(fun, args, acc, reducer, opts)
  end

  def reduce!(fun, args, acc, reducer, opts \\ [])

  def reduce!(_fun, [], acc, _reducer, _opts), do: acc
  def reduce!(fun, args, acc, reducer, opts) do
    opts = default_opts(opts)
    HexWeb.Parallel.Process.reduce(fun, args, acc, reducer!(reducer), opts)
  end

  defp reducer!(fun) do
    fn
      {:ok, value}, acc ->
        fun.(value, acc)
      {:error, _}, _acc ->
        raise "Parallel tasks failed"
    end
  end

  defp default_opts(opts) do
    opts
    |> Keyword.put(:parallel, parallel(opts[:parallel]))
    |> Keyword.put_new(:timeout, @timeout)
  end

  if Mix.env == :test do
    defp parallel(_arg), do: 1
  else
    defp parallel(arg), do: arg || @parallel
  end
end

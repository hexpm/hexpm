defmodule HexWeb.Parallel do
  use GenServer
  require Logger

  @timeout 60 * 1000
  @parallel 50

  def run(fun, args, opts \\ [])

  def run(_fun, [], _opts), do: []
  def run(fun, args, opts) do
    opts = default_opts(opts)
    num_args = length(args)

    if num_args > 1000 do
      HexWeb.Parallel.ETS.run(fun, num_args, args, opts)
    else
      HexWeb.Parallel.Process.run(fun, num_args, args, opts)
    end
  end

  def run!(fun, args, opts \\ [])

  def run!(fun, args, opts) do
    results = run(fun, args, opts)
    Enum.map(results, fn
      {:ok, value} ->
        value
      {:error, _} ->
        raise "Parallel tasks failed"
    end)
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

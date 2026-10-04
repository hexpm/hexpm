defmodule HexpmWeb.SyntaxHighlightHelpers do
  @moduledoc false

  alias HexpmWeb.SyntaxHighlight.Pool

  @module "defmodule App do\n  def run(value), do: IO.puts(\"<\#{value}>\")\nend\n"

  @doc """
  Elixir source that takes about `seconds` of CPU to highlight, at the
  throughput measured for this module repeated: 6.5 MB in 4 s on an M-series
  Mac.
  """
  def slow_source(seconds) do
    String.duplicate(@module, round(seconds * 25_000))
  end

  @doc """
  OS pids of the `lumis serve` processes `pool` holds idle.
  """
  def idle_os_pids(pool) do
    pool_pid = GenServer.whereis(pool)

    for port <- Port.list(),
        Port.info(port, :connected) == {:connected, pool_pid},
        {:os_pid, os_pid} <- [Port.info(port, :os_pid)],
        do: os_pid
  end

  def alive?(os_pid) do
    {_output, status} = System.cmd("kill", ["-0", to_string(os_pid)], stderr_to_stdout: true)
    status == 0
  end

  def wait_until(fun, attempts \\ 100) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)
    end
  end

  @doc """
  Starts a pool on a peer node from a process that stays alive, since the call
  that starts it does not.
  """
  def start_peer_pool(config, lumis_config) do
    Application.put_env(:hexpm, HexpmWeb.SyntaxHighlight, config)
    Application.put_all_env(lumis: lumis_config)
    parent = self()

    spawn(fn ->
      {:ok, pool} = Pool.start_link(config)
      send(parent, {:started, pool})
      Process.sleep(:infinity)
    end)

    receive do
      {:started, pool} -> idle_os_pids(pool)
    end
  end
end

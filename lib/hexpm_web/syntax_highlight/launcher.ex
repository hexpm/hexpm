defmodule HexpmWeb.SyntaxHighlight.Launcher do
  @moduledoc """
  How `lumis serve` processes start: the environment they get, the limits and
  sandbox they run under, and a check that all of it works before any of them
  start.

  `lumis serve` parses source from packages with native code, so it is kept
  apart from the VM and bounded. With the sandbox `:required` each one runs as

      prlimit --data=BYTES -- nice -n NICE --
        setpriv --nnp --pdeathsig KILL --seccomp-filter serve.bpf -- lumis ...

  and every step execs the next, so the port's OS process is `lumis` itself.

    * The seccomp filter refuses the network, signals to other processes and
      reading their memory, see `Mix.Tasks.Hexpm.LumisSeccomp`.
    * `--nnp` stops exec from granting privileges, and `--pdeathsig KILL` kills
      it if `erl_child_setup`, its parent, dies.
    * The data limit makes an allocation fail in that process before the
      container reaches its memory limit, where the OOM killer ends every
      process in it.

  It does not restrict files: the process can read and write what the VM's
  user can.

  With the sandbox `:off`, for development and for any OS but Linux, it gets
  only `nice`. Both get an empty environment.
  """

  @check_timeout 10_000

  @doc """
  The command `lumis` runs under, for `Lumis.Port.open/1`.
  """
  @spec wrapper(keyword()) :: [String.t()]
  def wrapper(config) do
    nice = [executable!("nice"), "-n", to_string(Keyword.fetch!(config, :nice)), "--"]

    case Keyword.fetch!(config, :sandbox) do
      :off ->
        nice

      :required ->
        max_data = Keyword.fetch!(config, :max_data_mb) * 1024 * 1024

        [executable!("prlimit"), "--data=#{max_data}", "--"] ++
          nice ++
          [executable!("setpriv"), "--nnp", "--pdeathsig", "KILL"] ++
          ["--seccomp-filter", seccomp_filter(config), "--"]
    end
  end

  @doc """
  Unsets every variable the VM has, since a port inherits all of them.
  """
  @spec env() :: Lumis.Port.env()
  def env() do
    for {name, _value} <- System.get_env(), do: {name, false}
  end

  @doc """
  Path of the seccomp filter, by default the one `mix hexpm.lumis_seccomp`
  writes.
  """
  def seccomp_filter(config) do
    Keyword.get_lazy(config, :seccomp_filter, fn ->
      Application.app_dir(:hexpm, "priv/lumis_sandbox/serve.bpf")
    end)
  end

  @doc """
  Starts one `lumis serve` the way the pool will and has it highlight, so a
  sandbox the kernel refuses or a `lumis` that cannot start is found once,
  rather than by every worker.
  """
  @spec check(keyword()) :: :ok | {:error, String.t()}
  def check(config) do
    with :ok <- check_platform(Keyword.fetch!(config, :sandbox)),
         {:ok, wrapper} <- check_wrapper(config) do
      port =
        Lumis.Port.open(
          wrapper: wrapper,
          env: env(),
          data_dir: Keyword.fetch!(config, :data_dir)
        )

      Port.command(port, Lumis.Port.request("", "check.txt"))

      receive do
        {^port, {:data, reply}} ->
          close(port)

          case Lumis.Port.decode_reply(reply) do
            {:ok, _html, _missing, _max_rss_kb} -> :ok
            other -> {:error, "lumis serve answered #{inspect(other)}"}
          end

        {^port, {:exit_status, status}} ->
          close(port)
          {:error, "lumis serve exited with status #{status}"}
      after
        @check_timeout ->
          close(port)
          {:error, "lumis serve did not answer within #{@check_timeout} ms"}
      end
    end
  end

  @doc """
  Closes a port this process owns and drops what it already sent, so nothing
  from it is left in the mailbox.
  """
  def close(port) do
    Process.unlink(port)

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    flush(port)
  end

  @doc """
  Drops messages a port already sent this process.
  """
  def flush(port) do
    receive do
      {^port, _message} -> flush(port)
      {:EXIT, ^port, _reason} -> flush(port)
    after
      0 -> :ok
    end
  end

  defp check_platform(:off), do: :ok

  defp check_platform(:required) do
    case :os.type() do
      {:unix, :linux} -> :ok
      os -> {:error, "the sandbox needs Linux, this is #{inspect(os)}"}
    end
  end

  defp check_wrapper(config) do
    with :required <- Keyword.fetch!(config, :sandbox),
         filter = seccomp_filter(config),
         false <- File.regular?(filter) do
      {:error, "#{filter} is missing, run mix hexpm.lumis_seccomp"}
    else
      _sandbox_off_or_filter_present -> {:ok, wrapper(config)}
    end
  rescue
    error in RuntimeError -> {:error, Exception.message(error)}
  end

  defp executable!(name) do
    System.find_executable(name) || raise "#{name} is not on the PATH"
  end
end

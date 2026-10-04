defmodule Mix.Tasks.Hexpm.LumisSeccomp do
  @moduledoc """
  Writes the seccomp filter `lumis serve` runs under to
  `priv/lumis_sandbox/serve.bpf`, with `enosys` from util-linux. Linux only.

      mix hexpm.lumis_seccomp [--output PATH]

  The filter makes these syscalls fail with `ENOSYS`:

    * the network, `socket` and `connect`
    * other processes, from reading their memory to signalling or reprioritizing
      them
    * namespaces and mounts
    * kernel interfaces the worker never needs, such as `bpf` and `io_uring`

  `execve` stays allowed, because `setpriv` loads the filter before it execs
  `lumis`. `tgkill` stays allowed,
  because `abort` uses it on the process's own threads. `prlimit64` stays
  allowed, because `lumis serve` sets its own CPU limit with it.

  A filter is for one CPU architecture, so it is written where it runs.
  """

  use Mix.Task

  @shortdoc "Writes the seccomp filter for lumis serve"

  @default_output "priv/lumis_sandbox/serve.bpf"

  @syscalls ~w(
    socket connect
    ptrace process_vm_readv process_vm_writev process_madvise
    kill tkill rt_sigqueueinfo rt_tgsigqueueinfo
    pidfd_open pidfd_getfd pidfd_send_signal
    setpriority sched_setaffinity sched_setattr sched_setparam sched_setscheduler
    mount umount2 unshare setns pivot_root
    bpf perf_event_open keyctl add_key request_key userfaultfd io_uring_setup
  )

  @impl Mix.Task
  def run(args) do
    {opts, _args} = OptionParser.parse!(args, strict: [output: :string])
    output = Path.expand(opts[:output] || @default_output)

    case write(output) do
      :ok -> Mix.shell().info("Wrote #{output}")
      {:error, message} -> Mix.raise(message)
    end
  end

  @doc false
  def write(output) do
    if enosys = System.find_executable("enosys") do
      File.mkdir_p!(Path.dirname(output))
      args = Enum.flat_map(@syscalls, &["--syscall", &1]) ++ ["--dump=#{output}"]

      case System.cmd(enosys, args, stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, status} -> {:error, "enosys exited with #{status}:\n#{output}"}
      end
    else
      {:error, "enosys is not on the PATH, it is in util-linux"}
    end
  end
end

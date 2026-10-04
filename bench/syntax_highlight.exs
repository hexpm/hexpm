# Times syntax highlighting in HexpmWeb.SyntaxHighlight.Pool, which runs
# `lumis serve` processes.
#
#     mix run --no-start bench/syntax_highlight.exs DIRECTORY
#
# Every file in DIRECTORY is an input, highlighted as its file name says.
# Files under 10 KB run 20 times and larger ones 10, after 2 warmups. It prints
# the median and p90 in ms of each input, the time from opening a port to its
# first reply, and the resident memory of a `lumis serve` process. With
# HEXPM_SYNTAX_HIGHLIGHT_SANDBOX=required it also runs the pool in its sandbox,
# which needs Linux and `mix hexpm.lumis_seccomp`.
#
# The lumis NIF is not timed: outside prod it is a debug build.
#
#     mix run --no-start bench/syntax_highlight.exs --contention FILE
#
# Measures how much CPU a busy Erlang process gets while FILE is highlighted,
# relative to running alone: by the NIF, and by `lumis serve` at nice 0 and 10.
# Run it on one CPU, such as with `taskset -c 0` or `docker run --cpuset-cpus 0`.
# FILE should take a few seconds to highlight; the NIF cannot be stopped, so the
# script waits for it.

alias HexpmWeb.SyntaxHighlight.{Launcher, Pool}

defmodule Bench do
  @warmup 2

  def environment() do
    "os=#{inspect(:os.type())} arch=#{:erlang.system_info(:system_architecture)} " <>
      "otp=#{System.otp_release()} elixir=#{System.version()} " <>
      "schedulers=#{System.schedulers_online()} " <>
      "dirty_cpu=#{:erlang.system_info(:dirty_cpu_schedulers_online)}"
  end

  def time(fun) do
    started = System.monotonic_time(:microsecond)
    result = fun.()
    {(System.monotonic_time(:microsecond) - started) / 1000, result}
  end

  def run(input, fun) do
    runs = if byte_size(input.source) < 10_000, do: 20, else: 10
    for _ <- 1..@warmup, do: fun.(input)

    samples =
      for _ <- 1..runs do
        {ms, _result} = time(fn -> fun.(input) end)
        ms
      end

    sorted = Enum.sort(samples)
    at = fn q -> Enum.at(sorted, min(runs - 1, floor(q * runs))) end
    "runs=#{runs} median_ms=#{format(at.(0.5))} p90_ms=#{format(at.(0.9))}"
  end

  def format(ms), do: :erlang.float_to_binary(ms, decimals: 2)

  def rss_kb(os_pid) do
    {output, 0} = System.cmd("ps", ["-o", "rss=", "-p", to_string(os_pid)])
    output |> String.trim() |> String.to_integer()
  end

  def request(port, source, language) do
    Port.command(port, Lumis.Port.request(source, language))

    receive do
      {^port, {:data, reply}} -> Lumis.Port.decode_reply(reply)
    after
      120_000 -> raise "no reply"
    end
  end

  def busy(ms) do
    deadline = System.monotonic_time(:millisecond) + ms
    busy(deadline, 0)
  end

  defp busy(deadline, count) do
    if rem(count, 10_000) == 0 and System.monotonic_time(:millisecond) >= deadline,
      do: count,
      else: busy(deadline, count + 1)
  end
end

{:ok, _apps} = Application.ensure_all_started([:lumis, :telemetry])

config =
  :hexpm
  |> Application.fetch_env!(HexpmWeb.SyntaxHighlight)
  |> Keyword.put(:data_dir, Lumis.Port.data_dir())

IO.puts("BENCHENV #{Bench.environment()}")

case System.argv() do
  ["--contention", path] ->
    source = File.read!(path)
    language = Path.basename(path)
    window = 3_000
    alone = Bench.busy(window)

    task =
      Task.async(fn ->
        Lumis.highlight!(source, formatter: {:html_linked, language: language})
      end)

    Process.sleep(100)
    share = Bench.busy(window) / alone
    IO.puts("CONTENTION design=nif share=#{Bench.format(share * 100)}%")
    Task.await(task, :infinity)

    for nice <- [0, 10] do
      port =
        Lumis.Port.open(
          wrapper: Launcher.wrapper(Keyword.merge(config, sandbox: :off, nice: nice)),
          env: Launcher.env(),
          preload: [language]
        )

      Bench.request(port, "", language)
      Port.command(port, Lumis.Port.request(source, language))
      Process.sleep(100)
      share = Bench.busy(window) / alone
      IO.puts("CONTENTION design=serve_nice_#{nice} share=#{Bench.format(share * 100)}%")
      Launcher.close(port)
    end

  [directory] ->
    inputs =
      for path <- directory |> File.ls!() |> Enum.sort(),
          File.regular?(Path.join(directory, path)),
          do: %{name: path, source: File.read!(Path.join(directory, path))}

    designs =
      for sandbox <- Enum.uniq([:off, config[:sandbox]]) do
        name = :"bench_pool_#{sandbox}"

        {:ok, _pool} =
          Pool.start_link(
            Keyword.merge(config,
              name: name,
              sandbox: sandbox,
              workers: 1,
              timeout: 120_000,
              cpu_limit_ms: 0
            )
          )

        {:"serve_#{sandbox}",
         fn input ->
           {:ok, _html} =
             Pool.highlight(input.source, input.name,
               name: name,
               timeout: 120_000,
               cpu_limit_ms: 0
             )
         end}
      end

    for input <- inputs, {design, fun} <- designs do
      IO.puts(
        "BENCH design=#{design} input=#{input.name} bytes=#{byte_size(input.source)} #{Bench.run(input, fun)}"
      )
    end

    for sandbox <- Enum.uniq([:off, config[:sandbox]]), preload <- [[], ["elixir"]] do
      wrapper = Launcher.wrapper(Keyword.put(config, :sandbox, sandbox))

      {ms, port} =
        Bench.time(fn ->
          port = Lumis.Port.open(wrapper: wrapper, env: Launcher.env(), preload: preload)
          {:ok, _html, _missing, _rss} = Bench.request(port, ":ok", "lib/app.ex")
          port
        end)

      IO.puts(
        "BENCHSTART sandbox=#{sandbox} preload=#{inspect(preload)} first_reply_ms=#{Bench.format(ms)}"
      )

      Launcher.close(port)
    end

    port =
      Lumis.Port.open(
        wrapper: Launcher.wrapper(config),
        env: Launcher.env(),
        preload: ["elixir", "erlang"]
      )

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    Bench.request(port, "", "check.txt")
    idle = Bench.rss_kb(os_pid)
    for input <- inputs, do: Bench.request(port, input.source, input.name)
    after_inputs = Bench.rss_kb(os_pid)
    small = Enum.min_by(inputs, &byte_size(&1.source))
    for _ <- 1..1_000, do: Bench.request(port, small.source, small.name)

    IO.puts(
      "BENCHMEM sandbox=#{config[:sandbox]} idle_rss_kb=#{idle} after_inputs_rss_kb=#{after_inputs} " <>
        "after_1000_requests_rss_kb=#{Bench.rss_kb(os_pid)}"
    )

    Launcher.close(port)
end

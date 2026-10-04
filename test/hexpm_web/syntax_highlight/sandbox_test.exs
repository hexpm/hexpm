defmodule HexpmWeb.SyntaxHighlight.SandboxTest do
  use ExUnit.Case, async: true

  import HexpmWeb.SyntaxHighlightHelpers

  alias HexpmWeb.SyntaxHighlight.{Launcher, Pool}

  @moduletag :sandbox
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} = context do
    filter = Path.join(tmp_dir, "serve.bpf")
    :ok = Mix.Tasks.Hexpm.LumisSeccomp.write(filter)

    name = :"#{inspect(context.module)} #{context.test}"

    config =
      :hexpm
      |> Application.fetch_env!(HexpmWeb.SyntaxHighlight)
      |> Keyword.merge(
        name: name,
        fetcher: :"#{name} fetcher",
        workers: 1,
        preload: ["elixir"],
        sandbox: :required,
        seccomp_filter: filter,
        data_dir: Lumis.Port.data_dir(),
        max_data_mb: 128,
        nice: 10
      )

    %{config: config, name: name}
  end

  test "highlights under the sandbox", %{config: config} do
    start_supervised!({Pool, config})

    assert {:ok, html} = Pool.highlight("value = <script>", "lib/app.ex", config)
    assert html =~ ~s(<span class="l-variable">value</span>)
  end

  test "runs without new privileges, under the filter, the data limit and nice", %{
    config: config,
    name: name
  } do
    start_supervised!({Pool, config})
    [os_pid] = idle_os_pids(name)

    status = File.read!("/proc/#{os_pid}/status")
    assert status =~ ~r/^NoNewPrivs:\s+1$/m
    assert status =~ ~r/^Seccomp:\s+2$/m

    assert File.read!("/proc/#{os_pid}/limits") =~
             ~r/^Max data size\s+134217728\s+134217728\s+bytes/m

    # Field 19 of stat, counted after the parenthesized command name.
    [_before, after_command] = String.split(File.read!("/proc/#{os_pid}/stat"), ") ", parts: 2)
    assert after_command |> String.split(" ") |> Enum.at(16) == "10"
  end

  test "is refused the network and signals", %{config: config} do
    {:ok, listener} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(listener)
    beam = System.pid()

    probes = [
      network: "exec 3<> /dev/tcp/127.0.0.1/#{port}",
      signal: "kill -0 #{beam}"
    ]

    for {probe, script} <- probes do
      assert {0, _output} = run_bash(script, :off, config), "#{probe} failed without the sandbox"

      assert {status, output} = run_bash(script, :required, config)
      assert status != 0, "#{probe} was allowed in the sandbox: #{output}"
      assert output =~ "Function not implemented"
    end

    assert {0, _output} = run_bash("exit 0", :required, config)
  end

  # Runs bash under the wrapper `lumis serve` gets.
  defp run_bash(script, sandbox, config) do
    bash = System.find_executable("bash")
    [program | args] = config |> Keyword.put(:sandbox, sandbox) |> Launcher.wrapper()

    port =
      Port.open({:spawn_executable, program}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args ++ [bash, "-c", script],
        env: for({name, false} <- Launcher.env(), do: {String.to_charlist(name), false})
      ])

    collect(port, "")
  end

  defp collect(port, output) do
    receive do
      {^port, {:data, data}} -> collect(port, output <> data)
      {^port, {:exit_status, status}} -> {status, output}
    after
      10_000 -> flunk("bash did not exit: #{output}")
    end
  end
end

defmodule HexpmWeb.SyntaxHighlight.PoolTest do
  use ExUnit.Case, async: true

  import HexpmWeb.SyntaxHighlightHelpers

  alias HexpmWeb.SyntaxHighlight.Pool

  setup context do
    name = :"#{inspect(context.module)} #{context.test}"
    %{name: name, opts: [name: name, workers: 1]}
  end

  test "highlights documents and lines in lumis serve", %{opts: opts} do
    opts = start_pool(opts)

    assert {:ok, html} = Pool.highlight(:document, "value = <script>", "lib/app.ex", opts)
    assert html =~ ~s(<pre class="lumis">)
    assert html =~ ~s(<span class="l-variable">value</span>)
    assert html =~ "&lt;"

    assert {:ok, [first, ""]} = Pool.highlight(:lines, "value = 1\n\n", "lib/app.ex", opts)
    assert first =~ ~s(<span class="l-variable">value</span>)
    refute first =~ "<pre"
  end

  test "a timeout closes the port, which ends the process", %{name: name, opts: opts} do
    opts = start_pool(opts)
    [os_pid] = idle_os_pids(name)

    assert {:error, :timeout} =
             Pool.highlight(
               :document,
               slow_source(1),
               "lib/app.ex",
               Keyword.put(opts, :timeout, 100)
             )

    assert wait_until(fn -> not alive?(os_pid) end)
    assert await_idle(opts[:name])
    assert {:ok, _html} = Pool.highlight(:document, ":ok", "lib/app.ex", opts)
  end

  test "the CPU limit ends a long highlight without the pool", %{opts: opts} do
    # The heap limit would end a source this large first.
    opts = start_pool(opts, max_data_mb: 1024)
    opts = Keyword.merge(opts, cpu_limit_ms: 1, timeout: 30_000)

    # 128 + SIGXCPU
    assert {:error, {:exit, 152}} = Pool.highlight(:document, slow_source(3), "lib/app.ex", opts)
    assert await_idle(opts[:name])
    assert {:ok, _html} = Pool.highlight(:document, ":ok", "lib/app.ex", opts)
  end

  test "a caller that dies during a highlight ends the process", %{name: name, opts: opts} do
    opts = start_pool(opts)
    [os_pid] = idle_os_pids(name)

    caller =
      spawn(fn ->
        Pool.highlight(
          :document,
          slow_source(2),
          "lib/app.ex",
          Keyword.put(opts, :timeout, 30_000)
        )
      end)

    assert wait_until(fn -> idle_os_pids(name) == [] end)
    Process.exit(caller, :kill)

    assert wait_until(fn -> not alive?(os_pid) end)
    assert await_idle(opts[:name])
    assert {:ok, _html} = Pool.highlight(:document, ":ok", "lib/app.ex", opts)
  end

  test "a process that crashes is replaced", %{name: name, opts: opts} do
    opts = start_pool(opts)
    [os_pid] = idle_os_pids(name)

    System.cmd("kill", ["-KILL", to_string(os_pid)])

    assert wait_until(fn -> match?([new] when new != os_pid, idle_os_pids(name)) end, 3_000)
    assert {:ok, _html} = Pool.highlight(:document, ":ok", "lib/app.ex", opts)
  end

  test "waits for a free process at most queue_timeout", %{name: name, opts: opts} do
    opts = start_pool(opts)

    task =
      Task.async(fn ->
        Pool.highlight(
          :document,
          slow_source(0.5),
          "lib/app.ex",
          Keyword.put(opts, :timeout, 30_000)
        )
      end)

    assert wait_until(fn -> idle_os_pids(name) == [] end)

    assert {:error, :queue_timeout} =
             Pool.highlight(:document, ":ok", "lib/app.ex", Keyword.put(opts, :queue_timeout, 50))

    assert {:ok, _html} = Task.await(task, 30_000)
  end

  test "replaces a process whose memory passed recycle_rss_mb", %{name: name, opts: opts} do
    opts = start_pool(opts, recycle_rss_mb: 1)
    [os_pid] = idle_os_pids(name)

    assert {:ok, _html} = Pool.highlight(:document, ":ok", "lib/app.ex", opts)

    assert wait_until(fn -> not alive?(os_pid) end)
    assert await_idle(name)
  end

  test "is unavailable when the pool is not running" do
    assert {:error, :unavailable} =
             Pool.highlight(:document, ":ok", "lib/app.ex", name: :no_such_pool)
  end

  test "processes stop when the VM is killed", %{opts: opts} do
    {:ok, peer, _node} =
      :peer.start(%{
        connection: :standard_io,
        args: Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
      })

    {:ok, _apps} = :peer.call(peer, Application, :ensure_all_started, [:nimble_pool])

    config = Keyword.merge(Application.fetch_env!(:hexpm, HexpmWeb.SyntaxHighlight), opts)
    lumis_config = Application.get_all_env(:lumis)

    [os_pid] =
      :peer.call(
        peer,
        HexpmWeb.SyntaxHighlightHelpers,
        :start_peer_pool,
        [config, lumis_config],
        60_000
      )

    assert alive?(os_pid)

    System.cmd("kill", ["-KILL", :peer.call(peer, System, :pid, [])])

    assert wait_until(fn -> not alive?(os_pid) end)
  end

  if :os.type() == {:unix, :linux} do
    test "processes run with the heap limit and nice value", %{name: name, opts: opts} do
      start_pool(opts, max_data_mb: 256, nice: 7)
      [os_pid] = idle_os_pids(name)

      assert File.read!("/proc/#{os_pid}/limits") =~
               ~r/Max data size\s+#{256 * 1024 * 1024}\s+#{256 * 1024 * 1024}\s+bytes/

      stat = File.read!("/proc/#{os_pid}/stat")
      [_pid_and_comm, fields] = String.split(stat, ") ", parts: 2)
      # The nice value is field 19 of stat, the 17th after the command.
      assert fields |> String.split(" ") |> Enum.at(16) == "7"
    end
  end

  defp start_pool(opts, overrides \\ []) do
    opts = Keyword.merge(opts, overrides)
    start_supervised!({Pool, opts})
    assert await_idle(opts[:name])
    opts
  end
end

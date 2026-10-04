defmodule HexpmWeb.SyntaxHighlight.PoolTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import HexpmWeb.SyntaxHighlightHelpers

  alias HexpmWeb.SyntaxHighlight.{Fetcher, Pool}

  setup context do
    name = :"#{inspect(context.module)} #{context.test}"
    opts = [name: name, fetcher: :"#{name} fetcher", workers: 1, preload: ["elixir"]]
    %{name: name, opts: opts}
  end

  test "highlights in lumis serve", %{opts: opts} do
    opts = start_pool(opts)

    assert {:ok, html} = Pool.highlight("value = <script>", "lib/app.ex", opts)
    assert html =~ ~s(<span class="l-variable">value</span>)
    assert html =~ "&lt;"
  end

  test "a timeout closes the port, which ends the process", %{name: name, opts: opts} do
    opts = start_pool(opts)
    [os_pid] = idle_os_pids(name)

    assert {:error, :timeout} =
             Pool.highlight(slow_source(1), "lib/app.ex", Keyword.put(opts, :timeout, 100))

    assert wait_until(fn -> not alive?(os_pid) end)
    assert {:ok, _html} = Pool.highlight(":ok", "lib/app.ex", opts)
  end

  test "the CPU limit ends a long highlight without the pool", %{opts: opts} do
    opts = start_pool(opts)
    opts = Keyword.merge(opts, cpu_limit_ms: 1, timeout: 30_000)

    # 128 + SIGXCPU
    assert {:error, {:exit, 152}} = Pool.highlight(slow_source(3), "lib/app.ex", opts)
    assert {:ok, _html} = Pool.highlight(":ok", "lib/app.ex", opts)
  end

  test "a caller that dies during a highlight ends the process", %{name: name, opts: opts} do
    opts = start_pool(opts)
    [os_pid] = idle_os_pids(name)

    caller =
      spawn(fn ->
        Pool.highlight(slow_source(2), "lib/app.ex", Keyword.put(opts, :timeout, 30_000))
      end)

    assert wait_until(fn -> idle_os_pids(name) == [] end)
    Process.exit(caller, :kill)

    assert wait_until(fn -> not alive?(os_pid) end)
    assert {:ok, _html} = Pool.highlight(":ok", "lib/app.ex", opts)
  end

  test "a process that crashes is replaced", %{name: name, opts: opts} do
    opts = start_pool(opts)
    [os_pid] = idle_os_pids(name)

    System.cmd("kill", ["-KILL", to_string(os_pid)])

    assert wait_until(fn -> match?([new] when new != os_pid, idle_os_pids(name)) end)
    assert {:ok, _html} = Pool.highlight(":ok", "lib/app.ex", opts)
  end

  test "waits for a free process at most queue_timeout", %{name: name, opts: opts} do
    opts = start_pool(opts)

    task =
      Task.async(fn ->
        Pool.highlight(slow_source(0.5), "lib/app.ex", Keyword.put(opts, :timeout, 30_000))
      end)

    assert wait_until(fn -> idle_os_pids(name) == [] end)

    assert {:error, :queue_timeout} =
             Pool.highlight(":ok", "lib/app.ex", Keyword.put(opts, :queue_timeout, 50))

    assert {:ok, _html} = Task.await(task, 30_000)
  end

  test "replaces a process whose memory passed recycle_rss_mb", %{name: name, opts: opts} do
    opts = start_pool(opts, recycle_rss_mb: 1)
    [os_pid] = idle_os_pids(name)

    assert {:ok, _html} = Pool.highlight(":ok", "lib/app.ex", opts)

    assert wait_until(fn -> not alive?(os_pid) end)
    assert wait_until(fn -> match?([_new], idle_os_pids(name)) end)
  end

  test "is unavailable when the pool is not running" do
    assert {:error, :unavailable} = Pool.highlight(":ok", "lib/app.ex", name: :no_such_pool)
  end

  test "processes get none of the VM's environment", %{name: name, opts: opts} do
    System.put_env("HEXPM_SYNTAX_HIGHLIGHT_TEST_CANARY", "secret")
    on_exit(fn -> System.delete_env("HEXPM_SYNTAX_HIGHLIGHT_TEST_CANARY") end)

    # A port opened without an environment inherits the VM's, which shows the
    # check below would see it. Each process answers a request before its
    # environment is read, because until erl_child_setup has exec'd lumis the
    # pid shows erl_child_setup's environment.
    inheriting = Lumis.Port.open()
    {:os_pid, inheriting_os_pid} = Port.info(inheriting, :os_pid)
    Port.command(inheriting, Lumis.Port.request(":ok", "lib/app.ex"))
    assert_receive {^inheriting, {:data, _reply}}, 5_000
    assert process_environment(inheriting_os_pid) =~ "PATH="
    Port.close(inheriting)

    opts = start_pool(opts)
    [os_pid] = idle_os_pids(name)
    assert {:ok, _html} = Pool.highlight(":ok", "lib/app.ex", opts)

    environment = process_environment(os_pid)
    refute environment =~ "HEXPM_SYNTAX_HIGHLIGHT_TEST_CANARY"
    refute environment =~ "PATH="
  end

  test "processes stop when the VM is killed", %{opts: opts} do
    {:ok, peer, _node} =
      :peer.start(%{
        connection: :standard_io,
        args: Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
      })

    {:ok, _apps} = :peer.call(peer, Application, :ensure_all_started, [:logger])

    config = Keyword.merge(Application.fetch_env!(:hexpm, HexpmWeb.SyntaxHighlight), opts)
    lumis_config = Application.get_all_env(:lumis)

    [os_pid] =
      :peer.call(peer, HexpmWeb.SyntaxHighlightHelpers, :start_peer_pool, [config, lumis_config])

    assert alive?(os_pid)

    System.cmd("kill", ["-KILL", :peer.call(peer, System, :pid, [])])

    assert wait_until(fn -> not alive?(os_pid) end)
  end

  @tag :tmp_dir
  test "downloads a language it did not have, after which it highlights", %{
    name: name,
    opts: opts,
    tmp_dir: tmp_dir
  } do
    start_supervised!({Fetcher, name: opts[:fetcher], data_dir: tmp_dir})
    opts = start_pool(opts, data_dir: tmp_dir, preload: [])

    assert {:error, :not_cached} = Pool.highlight("-module(app).", "src/app.erl", opts)

    assert wait_until(
             fn -> match?({:ok, _html}, Pool.highlight("-module(app).", "src/app.erl", opts)) end,
             3_000
           )

    assert [_os_pid] = idle_os_pids(name)
  end

  test "the start check fails without Linux for the sandbox", %{opts: opts} do
    if :os.type() == {:unix, :linux} do
      :ok
    else
      log =
        capture_log(fn ->
          assert {:ok, :undefined} =
                   start_supervised({Pool, Keyword.put(opts, :sandbox, :required)})
        end)

      assert log =~ "the sandbox needs Linux"
      assert {:error, :unavailable} = Pool.highlight(":ok", "lib/app.ex", opts)
    end
  end

  defp start_pool(opts, overrides \\ []) do
    opts = Keyword.merge(opts, overrides)
    start_supervised!({Pool, opts})
    opts
  end

  defp process_environment(os_pid) do
    case :os.type() do
      {:unix, :linux} ->
        "/proc/#{os_pid}/environ" |> File.read!() |> String.replace(<<0>>, "\n")

      {:unix, :darwin} ->
        {output, 0} = System.cmd("ps", ["-E", "-ww", "-o", "command=", "-p", to_string(os_pid)])
        output
    end
  end
end

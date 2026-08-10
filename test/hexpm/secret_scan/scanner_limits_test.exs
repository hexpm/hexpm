defmodule Hexpm.SecretScan.ScannerLimitsTest do
  # Not async: the budgets are application environment, which is global.
  use ExUnit.Case, async: false

  alias Hexpm.SecretScan.Scanner

  setup do
    dir = Path.join(System.tmp_dir!(), "secret-scan-limits-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "a file built to defeat the prefilter is abandoned, not scanned", %{dir: dir} do
    # Four vendor rules cost ~210 ms/KB on keyword-dense input, a thousand
    # times the rest. A 32 KB file of them gzips to 85 bytes, so a tarball
    # well under the publish limit holds thousands. Budgets are shrunk here
    # rather than spending the real thirty seconds.
    Hexpm.TestHelpers.app_env(:hexpm, :secret_scan_file_timeout, 50)
    Hexpm.TestHelpers.app_env(:hexpm, :secret_scan_release_timeout, 200)
    slow = String.duplicate("meraki", 2730) <> String.duplicate("a", 16382)
    paths = for n <- 1..40, do: write_path(dir, "slow_#{n}.txt", slow)

    log =
      Hexpm.TestHelpers.capture_debug_log(fn ->
        assert {[], true} = Scanner.scan_files(dir, paths, scope: :all)
      end)

    assert log =~ "incomplete"
  end

  test "the release budget is a ceiling, not a suggestion", %{dir: dir} do
    # Every slot busy with a file that outlasts the budget, and a file timeout
    # far past it. Reading the clock only when a result arrives would sit here
    # for as long as the slowest file takes rather than stopping at 300 ms.
    Hexpm.TestHelpers.app_env(:hexpm, :secret_scan_file_timeout, 60_000)
    Hexpm.TestHelpers.app_env(:hexpm, :secret_scan_release_timeout, 300)
    slow = String.duplicate("meraki", 2730) <> String.duplicate("a", 16382)

    paths =
      for n <- 1..(System.schedulers_online() * 2), do: write_path(dir, "slow_#{n}.txt", slow)

    {elapsed, _log} =
      :timer.tc(fn ->
        Hexpm.TestHelpers.capture_debug_log(fn ->
          assert {[], true} = Scanner.scan_files(dir, paths, scope: :all)
        end)
      end)

    assert div(elapsed, 1000) < 2_000
  end

  defp write(dir, path, contents) do
    full = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)
  end

  defp write_path(dir, path, contents) do
    write(dir, path, contents)
    path
  end
end

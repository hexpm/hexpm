defmodule Hexpm.SecretScan.ScannerTimeoutTest do
  # The budgets are read from application env, which is global, so this can't
  # run beside the rest of the scanner tests.
  use ExUnit.Case, async: false

  alias Hexpm.SecretScan.Scanner

  @github_token "ghp_" <> "016Cq2mKvXbNzR8dLpWyTuAeH3jFgS4iOU7Q"

  setup do
    dir = Path.join(System.tmp_dir!(), "secret-scan-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
      Application.delete_env(:hexpm, :secret_scan_file_timeout)
      Application.delete_env(:hexpm, :secret_scan_release_timeout)
    end)

    {:ok, dir: dir}
  end

  test "a file that outruns its budget doesn't take the ones beside it", %{dir: dir} do
    # Keyword-dense, so the prefilter skips nothing and every rule runs: a
    # megabyte of it takes over a second against the 100 ms budget below.
    write(
      dir,
      "slow.txt",
      String.duplicate(~s|okta = "sumo meraki api key secret auth"\n|, 25_000)
    )

    write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")
    Application.put_env(:hexpm, :secret_scan_file_timeout, 100)

    log =
      Hexpm.TestHelpers.capture_debug_log(fn ->
        assert {[finding], true} = Scanner.scan_files(dir, ["slow.txt", ".env"], scope: :all)
        assert finding.file_path == ".env"
      end)

    assert log =~ "1 files timed out"
  end

  test "the release budget stops the scan and marks it incomplete", %{dir: dir} do
    write(dir, ".env", "GITHUB_TOKEN=#{@github_token}\n")
    Application.put_env(:hexpm, :secret_scan_release_timeout, -1)

    log =
      Hexpm.TestHelpers.capture_debug_log(fn ->
        assert {[], true} = Scanner.scan_files(dir, [".env"])
      end)

    assert log =~ "incomplete"
    assert log =~ "budget"
  end

  defp write(dir, path, content) do
    full = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
  end
end

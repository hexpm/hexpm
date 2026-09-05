defmodule Hexpm.RepoRetargetTest do
  # Restarts the shared database pool, so nothing else may be running.
  use ExUnit.Case, async: false

  # A restarted pool comes up in the ownership default mode (:auto), not the
  # :manual sandbox mode test_helper configured; without restoring it, every
  # test that runs afterwards commits real rows and the suite flakes on
  # whatever runs downstream.
  defp retarget_and_restore_sandbox!(target_port) do
    :ok = Hexpm.Repo.retarget_port!(target_port)
    Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, :manual)
    :ok
  end

  test "retarget_port! restarts the pool against the requested port" do
    config = Application.fetch_env!(:hexpm, Hexpm.RepoBase)
    port = config[:port] || 5432

    assert :ok = retarget_and_restore_sandbox!(port)
    assert Application.fetch_env!(:hexpm, Hexpm.RepoBase)[:port] == port

    # The restarted pool is a fresh sandbox in manual mode; prove it serves
    # queries again after the restart.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
    assert %{rows: [[1]]} = Hexpm.RepoBase.query!("SELECT 1")
    Ecto.Adapters.SQL.Sandbox.checkin(Hexpm.RepoBase)
  end

  test "retarget_port! rewrites HEXPM_DATABASE_URL, which init/2 prefers over config" do
    config = Application.fetch_env!(:hexpm, Hexpm.RepoBase)
    port = config[:port] || 5432

    # A dead port in the environment variable proves the rewrite happens:
    # init/2 re-reads the variable on pool start, so without the rewrite the
    # restarted pool would target 1 and fail its queries.
    System.put_env(
      "HEXPM_DATABASE_URL",
      "ecto://#{config[:username]}:#{config[:password]}@#{config[:hostname]}:1/#{config[:database]}"
    )

    on_exit(fn ->
      System.delete_env("HEXPM_DATABASE_URL")
      :ok = retarget_and_restore_sandbox!(port)
    end)

    assert :ok = retarget_and_restore_sandbox!(port)
    assert URI.parse(System.get_env("HEXPM_DATABASE_URL")).port == port

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
    assert %{rows: [[1]]} = Hexpm.RepoBase.query!("SELECT 1")
    Ecto.Adapters.SQL.Sandbox.checkin(Hexpm.RepoBase)
  end
end

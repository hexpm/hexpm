defmodule Hexpm.WriteModeTest do
  use ExUnit.Case, async: false

  alias Hexpm.WriteMode

  setup do
    on_exit(fn -> WriteMode.configure!(false) end)
    :ok
  end

  test "mode reflects the configured value" do
    assert WriteMode.mode() == :write
    refute WriteMode.enabled?()

    WriteMode.configure!(:hold)
    assert WriteMode.mode() == :hold
    refute WriteMode.enabled?()

    WriteMode.configure!(true)
    assert WriteMode.mode() == :read_only
    assert WriteMode.enabled?()
  end

  test "await_write passes writes through in write mode and rejects them in read-only" do
    assert WriteMode.await_write(100) == :ok

    WriteMode.configure!(true)
    assert WriteMode.await_write(100) == :unavailable
  end

  test "await_write parks during hold and releases when writes resume" do
    WriteMode.configure!(:hold)

    task = Task.async(fn -> WriteMode.await_write(5000) end)
    assert nil == Task.yield(task, 100)

    WriteMode.configure!(false)
    assert Task.await(task) == :ok
  end

  test "await_write parks during hold and rejects when the mode hardens to read-only" do
    WriteMode.configure!(:hold)

    task = Task.async(fn -> WriteMode.await_write(5000) end)
    assert nil == Task.yield(task, 100)

    WriteMode.configure!(true)
    assert Task.await(task) == :unavailable
  end

  test "await_write times out when the hold outlives the deadline" do
    WriteMode.configure!(:hold)
    assert WriteMode.await_write(50) == :timeout
  end

  test "await_write also parks during hold_all" do
    WriteMode.configure!(:hold_all)

    task = Task.async(fn -> WriteMode.await_write(5000) end)
    assert nil == Task.yield(task, 100)

    # Narrowing to the write-only hold keeps writes parked.
    WriteMode.configure!(:hold)
    assert nil == Task.yield(task, 100)

    WriteMode.configure!(false)
    assert Task.await(task) == :ok
  end

  test "await_read passes in every mode except hold_all" do
    assert WriteMode.await_read(100) == :ok

    WriteMode.configure!(:hold)
    assert WriteMode.await_read(100) == :ok

    WriteMode.configure!(true)
    assert WriteMode.await_read(100) == :ok
  end

  test "await_read parks during hold_all and releases on any other mode" do
    WriteMode.configure!(:hold_all)

    task = Task.async(fn -> WriteMode.await_read(5000) end)
    assert nil == Task.yield(task, 100)

    WriteMode.configure!(:hold)
    assert Task.await(task) == :ok
  end

  test "await_read times out when hold_all outlives the deadline" do
    WriteMode.configure!(:hold_all)
    assert WriteMode.await_read(50) == :timeout
  end

  test "a broadcast from another node applies the mode locally" do
    Phoenix.PubSub.broadcast!(Hexpm.PubSub, "write_mode", {:write_mode, :hold})

    # The listener applies the mode asynchronously.
    assert wait_until(fn -> WriteMode.mode() == :hold end)
  end

  defp wait_until(fun, tries \\ 50) do
    cond do
      fun.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(10)
        wait_until(fun, tries - 1)
    end
  end
end

defmodule Hexpm.Hexdocs.DebouncerTest do
  use ExUnit.Case, async: true

  alias Hexpm.Hexdocs.Debouncer

  setup do
    %{debouncer: start_supervised!(Debouncer)}
  end

  test "runs the first call for a key immediately", %{debouncer: debouncer} do
    test_pid = self()

    assert {:ok, :sent} =
             Debouncer.debounce(debouncer, :key, 1_000, fn ->
               send(test_pid, :ran)
               :sent
             end)

    assert_receive :ran
  end

  test "runs one waiting call at the next deadline and debounces the rest", %{
    debouncer: debouncer
  } do
    test_pid = self()

    assert {:ok, :first} = Debouncer.debounce(debouncer, :key, 60_000, fn -> :first end)

    second =
      Task.async(fn ->
        Debouncer.debounce(debouncer, :key, 60_000, fn ->
          send(test_pid, :second_ran)
          :second
        end)
      end)

    third =
      Task.async(fn ->
        Debouncer.debounce(debouncer, :key, 60_000, fn ->
          send(test_pid, :third_ran)
          :third
        end)
      end)

    wait_for_waiters(debouncer, 2)
    send(debouncer, {:deadline, :key, 60_000})

    results = [Task.await(second), Task.await(third)]
    assert {:ok, :second} in results or {:ok, :third} in results
    assert :debounced in results

    assert_receive message when message in [:second_ran, :third_ran]
    refute_receive :second_ran, 10
    refute_receive :third_ran, 10
  end

  defp wait_for_waiters(debouncer, expected, attempts \\ 100)

  defp wait_for_waiters(_debouncer, _expected, 0),
    do: flunk("debouncer calls did not start")

  defp wait_for_waiters(debouncer, expected, attempts) do
    case :sys.get_state(debouncer) do
      %{key: waiters} when length(waiters) == expected ->
        :ok

      _state ->
        Process.sleep(1)
        wait_for_waiters(debouncer, expected, attempts - 1)
    end
  end
end

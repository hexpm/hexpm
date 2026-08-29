defmodule Hexpm.PromExTest do
  use ExUnit.Case, async: false

  defp oban_plugin() do
    Enum.find(Hexpm.PromEx.plugins(), fn
      {PromEx.Plugins.Oban, _opts} -> true
      _plugin -> false
    end)
  end

  defp put_queues(queues) do
    Application.put_env(
      :hexpm,
      Oban,
      Keyword.put(Application.fetch_env!(:hexpm, Oban), :queues, queues)
    )
  end

  setup do
    config = Application.fetch_env!(:hexpm, Oban)
    on_exit(fn -> Application.put_env(:hexpm, Oban, config) end)
    :ok
  end

  test "reports Oban metrics only on nodes that run queues" do
    put_queues(false)
    refute oban_plugin()

    put_queues([])
    refute oban_plugin()

    put_queues(registry: 1)
    assert {PromEx.Plugins.Oban, poll_rate: 60_000} = oban_plugin()
  end
end

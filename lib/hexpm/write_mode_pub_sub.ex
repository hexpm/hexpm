defmodule Hexpm.WriteModePubSub do
  use GenServer

  alias Hexpm.WriteMode

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def configure(mode) do
    GenServer.call(__MODULE__, {:configure, mode})
  end

  def init([]) do
    WriteMode.subscribe()
    {:ok, []}
  end

  # Serializing local sets and remote broadcasts through this process keeps a
  # node's mode from being overwritten by its own earlier broadcast.
  def handle_call({:configure, mode}, _from, []) do
    Application.put_env(:hexpm, :read_only_mode, mode)
    WriteMode.broadcast_from!(self(), mode)
    {:reply, :ok, []}
  end

  def handle_info({:write_mode, mode}, []) do
    Application.put_env(:hexpm, :read_only_mode, mode)
    {:noreply, []}
  end
end

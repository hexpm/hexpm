defmodule HexpmWeb.RateLimitPubSub do
  use GenServer
  alias HexpmWeb.Plugs.Attack

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def broadcast(key, time) do
    server = GenServer.whereis(__MODULE__)
    Phoenix.PubSub.broadcast_from!(Hexpm.PubSub, server, "ratelimit", {:throttle, key, time})
  end

  def init([]) do
    Phoenix.PubSub.subscribe(Hexpm.PubSub, "ratelimit")
    {:ok, []}
  end

  def handle_info({:throttle, {:user, user_id}, time}, []) do
    Attack.user_throttle(user_id, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:organization, organization_id}, time}, []) do
    Attack.organization_throttle(organization_id, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:ip, ip}, time}, []) do
    Attack.ip_throttle(ip, time: time)
    {:noreply, []}
  end
end

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

  def handle_info({:throttle, {:diff, identity}, time}, []) do
    Attack.diff_throttle(identity, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_start_ip, ip}, time}, []) do
    Attack.sso_start_ip_throttle(ip, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_start_organization, organization_id, ip}, time}, []) do
    Attack.sso_start_organization_throttle(organization_id, ip, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_discovery_ip, ip}, time}, []) do
    Attack.sso_discovery_ip_throttle(ip, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_discovery_domain, domain_hash, ip}, time}, []) do
    Attack.sso_discovery_domain_throttle(domain_hash, ip, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_link_ip, ip}, time}, []) do
    Attack.sso_link_ip_throttle(ip, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_link_organization, organization_id}, time}, []) do
    Attack.sso_link_organization_throttle(organization_id, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_link_subject, subject_hash}, time}, []) do
    Attack.sso_link_subject_throttle(subject_hash, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_link_email, email_hash}, time}, []) do
    Attack.sso_link_email_throttle(email_hash, time: time)
    {:noreply, []}
  end

  def handle_info({:throttle, {:sso_callback_ip, ip}, time}, []) do
    Attack.sso_callback_ip_throttle(ip, time: time)
    {:noreply, []}
  end
end

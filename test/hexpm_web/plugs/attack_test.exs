defmodule HexpmWeb.Plugs.AttackTest do
  use ExUnit.Case
  import Plug.{Conn, Test}
  import Hexpm.Factory
  alias HexpmWeb.{Plugs.Attack, RateLimitPubSub}

  defmodule Hello do
    # need to use Phoenix.Controller because RateLimit.Plug uses ErrorView
    # which in turn requires `plug :accepts`
    use Phoenix.Controller, formats: [json: "View"]

    plug :accepts, ~w(json)
    plug HexpmWeb.Plugs.Attack

    def index(conn, _params) do
      send_resp(conn, 200, "Hello, World!")
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
    %{user: insert(:user)}
  end

  describe "throttle" do
    test "allows unauthenticated requests when limit is not exceeded" do
      conn = request_ip({0, 0, 0, 0})
      assert conn.status == 200
      assert get_resp_header(conn, "x-ratelimit-limit") == ["100"]
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["99"]
    end

    test "allows authenticated requests when limit is not exceeded", %{user: user} do
      conn = request_user(user)
      assert conn.status == 200
      assert get_resp_header(conn, "x-ratelimit-limit") == ["500"]
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["499"]
    end

    test "broadcasts user rate limits", %{user: user} do
      align_to_throttle_bucket()
      time = System.system_time(:millisecond)
      Phoenix.PubSub.broadcast!(Hexpm.PubSub, "ratelimit", {:throttle, {:user, user.id}, time})
      Phoenix.PubSub.broadcast!(Hexpm.PubSub, "ratelimit", {:throttle, {:user, -1}, time})
      :sys.get_state(RateLimitPubSub)

      assert {:allow, {:throttle, data}} = Attack.user_throttle(user.id, time: time)
      assert data[:limit] == 500
      assert data[:remaining] == 498
    end

    test "broadcasts ip rate limits" do
      align_to_throttle_bucket()
      time = System.system_time(:millisecond)
      Phoenix.PubSub.broadcast!(Hexpm.PubSub, "ratelimit", {:throttle, {:ip, {3, 3, 3, 3}}, time})
      Phoenix.PubSub.broadcast!(Hexpm.PubSub, "ratelimit", {:throttle, {:ip, {4, 4, 4, 4}}, time})
      :sys.get_state(RateLimitPubSub)

      assert {:allow, {:throttle, data}} = Attack.ip_throttle({3, 3, 3, 3}, time: time)
      assert data[:limit] == 100
      assert data[:remaining] == 98
    end

    test "broadcasts and bounds diff generation rate limits" do
      align_to_throttle_bucket()
      identity = {:ip, {5, 5, 5, 5}}
      time = System.system_time(:millisecond)

      Phoenix.PubSub.broadcast!(
        Hexpm.PubSub,
        "ratelimit",
        {:throttle, {:diff, identity}, time}
      )

      :sys.get_state(RateLimitPubSub)

      assert {:allow, {:throttle, data}} = Attack.diff_throttle(identity, time: time)
      assert data[:limit] == 20
      assert data[:remaining] == 18

      for _ <- 1..18 do
        assert {:allow, _data} = Attack.diff_throttle(identity, time: time)
      end

      assert {:block, _data} = Attack.diff_throttle(identity, time: time)
    end

    test "broadcasts machine token exchange rate limits" do
      align_to_throttle_bucket()
      time = System.system_time(:millisecond)

      Phoenix.PubSub.broadcast!(
        Hexpm.PubSub,
        "ratelimit",
        {:throttle, {:machine_token_exchange, 123}, time}
      )

      :sys.get_state(RateLimitPubSub)

      assert {:allow, {:throttle, data}} =
               Attack.machine_token_exchange_throttle(123, time: time)

      assert data[:limit] == 100
      assert data[:remaining] == 98
    end

    test "limits machine token exchanges per API key" do
      time = System.system_time(:millisecond)

      Enum.each(1..100, fn _ ->
        assert {:allow, _data} = Attack.machine_token_exchange_throttle(456, time: time)
      end)

      assert {:block, _data} = Attack.machine_token_exchange_throttle(456, time: time)
      assert {:allow, _data} = Attack.machine_token_exchange_throttle(789, time: time)
    end

    test "halts requests when ip limit is exceeded" do
      align_to_throttle_bucket()

      Enum.each(99..0//-1, fn i ->
        conn = request_ip({1, 1, 1, 1})
        assert conn.status == 200
        assert get_resp_header(conn, "x-ratelimit-remaining") == ["#{i}"]
      end)

      conn = request_ip({1, 1, 1, 1})
      assert conn.status == 429

      assert conn.resp_body ==
               JSON.encode!(%{status: 429, message: "API rate limit exceeded for IP 1.1.1.1"})
    end

    test "halts requests when user limit is exceeded", %{user: user} do
      align_to_throttle_bucket()

      Enum.each(499..0//-1, fn i ->
        conn = request_user(user)
        assert conn.status == 200
        assert get_resp_header(conn, "x-ratelimit-remaining") == ["#{i}"]
      end)

      conn = request_user(user)
      assert conn.status == 429

      assert conn.resp_body ==
               JSON.encode!(%{
                 status: 429,
                 message: "API rate limit exceeded for user #{user.id}"
               })
    end

    test "allows requests again when limit expired" do
      conn = request_ip({2, 2, 2, 2})
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["99"]

      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

      conn = request_ip({2, 2, 2, 2})
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["99"]
    end

    test "doesn't limit requests from 127.0.0.1" do
      conn = request_ip({127, 0, 0, 1})
      assert conn.status == 200
      assert get_resp_header(conn, "x-ratelimit-remaining") == []
    end

    test "doesn't limit requests from CDN" do
      Hexpm.BlockAddress.reload()
      conn = request_ip({127, 0, 0, 255})
      assert conn.status == 200
      assert get_resp_header(conn, "x-ratelimit-remaining") == []
    end

    test "doesn't limit requests from service accounts", %{user: user} do
      Hexpm.BlockAddress.reload()
      user = Hexpm.Repo.update!(Ecto.Changeset.change(user, service: true))

      conn = request_user(user)
      assert conn.status == 200
      assert get_resp_header(conn, "x-ratelimit-remaining") == []
    end
  end

  describe "block addresses" do
    test "allows requests from IPs that are not blocked" do
      conn = request_ip({0, 0, 0, 0})
      assert conn.status == 200
      assert conn.resp_body == "Hello, World!"
    end

    test "halts requests from IPs that are blocked" do
      insert(:block_address, ip: "10.1.1.1")
      Hexpm.BlockAddress.reload()

      conn = request_ip({10, 1, 1, 1})
      assert conn.status == 403
      assert conn.resp_body == JSON.encode!(%{status: 403, message: "Blocked"})
    end

    test "halts requests from IPs that are blocked outside of /api" do
      insert(:block_address, ip: "10.1.1.1")
      Hexpm.BlockAddress.reload()

      conn = %{request_ip({10, 1, 1, 1}) | request_path: "/"}
      assert conn.status == 403
      assert conn.resp_body == JSON.encode!(%{status: 403, message: "Blocked"})
    end

    test "halts requests from IP masks that are blocked" do
      insert(:block_address, ip: "10.1.1.0/24")
      Hexpm.BlockAddress.reload()

      conn = request_ip({10, 1, 1, 1})
      assert conn.status == 403
      assert conn.resp_body == JSON.encode!(%{status: 403, message: "Blocked"})

      conn = request_ip({10, 1, 1, 127})
      assert conn.status == 403
      assert conn.resp_body == JSON.encode!(%{status: 403, message: "Blocked"})

      conn = request_ip({10, 1, 1, 255})
      assert conn.status == 403
      assert conn.resp_body == JSON.encode!(%{status: 403, message: "Blocked"})

      conn = request_ip({10, 1, 2, 0})
      assert conn.status == 200

      conn = request_ip({10, 1, 0, 0})
      assert conn.status == 200
    end

    test "allows requests again when the IP is unblocked" do
      blocked_address = insert(:block_address, ip: "20.2.2.2")
      Hexpm.BlockAddress.reload()

      conn = request_ip({20, 2, 2, 2})
      assert conn.status == 403
      assert conn.resp_body == JSON.encode!(%{status: 403, message: "Blocked"})

      Hexpm.Repo.delete!(blocked_address)
      Hexpm.BlockAddress.reload()

      conn = request_ip({20, 2, 2, 2})
      assert conn.status == 200
      assert conn.resp_body == "Hello, World!"
    end
  end

  describe "login ip throttle" do
    test "allows login requests when limit is not exceeded" do
      result = HexpmWeb.Plugs.Attack.login_ip_throttle({1, 1, 1, 1})
      assert {:allow, _data} = result
    end

    test "blocks login requests when IP limit is exceeded" do
      # Exhaust IP limit (10 attempts per 15 minutes)
      Enum.each(1..10, fn _ ->
        HexpmWeb.Plugs.Attack.login_ip_throttle({2, 2, 2, 2})
      end)

      result = HexpmWeb.Plugs.Attack.login_ip_throttle({2, 2, 2, 2})
      assert {:block, _data} = result
    end
  end

  describe "tfa throttle" do
    test "allows 2FA requests when limit is not exceeded" do
      result = HexpmWeb.Plugs.Attack.tfa_ip_throttle({5, 5, 5, 5})
      assert {:allow, _data} = result

      tfa_user_id = %{"uid" => 123, "return" => "/"}
      result = HexpmWeb.Plugs.Attack.tfa_session_throttle(tfa_user_id)
      assert {:allow, _data} = result
    end

    test "blocks 2FA requests when session limit is exceeded" do
      tfa_user_id = %{"uid" => 456, "return" => "/"}

      # Exhaust session limit (5 attempts per 10 minutes)
      Enum.each(1..5, fn _ ->
        HexpmWeb.Plugs.Attack.tfa_session_throttle(tfa_user_id)
      end)

      result = HexpmWeb.Plugs.Attack.tfa_session_throttle(tfa_user_id)
      assert {:block, _data} = result
    end

    test "blocks 2FA requests when IP limit is exceeded" do
      # Exhaust IP limit (20 attempts per 15 minutes)
      Enum.each(1..20, fn _ ->
        HexpmWeb.Plugs.Attack.tfa_ip_throttle({7, 7, 7, 7})
      end)

      result = HexpmWeb.Plugs.Attack.tfa_ip_throttle({7, 7, 7, 7})
      assert {:block, _data} = result
    end

    test "different TFA sessions have independent limits" do
      tfa_user_id_1 = %{"uid" => 111, "return" => "/"}
      tfa_user_id_2 = %{"uid" => 222, "return" => "/"}

      # Exhaust limit for first session
      Enum.each(1..5, fn _ ->
        HexpmWeb.Plugs.Attack.tfa_session_throttle(tfa_user_id_1)
      end)

      # First session should be blocked
      result1 = HexpmWeb.Plugs.Attack.tfa_session_throttle(tfa_user_id_1)
      assert {:block, _data} = result1

      # Second session should still work
      result2 = HexpmWeb.Plugs.Attack.tfa_session_throttle(tfa_user_id_2)
      assert {:allow, _data} = result2
    end
  end

  # The throttle counter is keyed by `div(time_ms, period_ms)`. If a test's
  # setup and assertion fall in different buckets, the counter resets between
  # them. Wait past the next boundary if we're too close to it.
  defp align_to_throttle_bucket(period_ms \\ 60_000, headroom_ms \\ 5_000) do
    remaining = period_ms - rem(System.system_time(:millisecond), period_ms)
    if remaining < headroom_ms, do: Process.sleep(remaining + 50)
  end

  defp request_ip(remote_ip) do
    conn(:get, "/api/")
    |> Map.put(:remote_ip, remote_ip)
    |> assign(:current_user, nil)
    |> assign(:current_organization, nil)
    |> Hello.call(:index)
  end

  defp request_user(user) do
    conn(:get, "/api/")
    |> Map.put(:remote_ip, {10, 0, 0, 1})
    |> assign(:current_user, user)
    |> assign(:current_organization, nil)
    |> Hello.call(:index)
  end
end

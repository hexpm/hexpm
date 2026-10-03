defmodule Hexpm.Accounts.OrganizationDomains.ResolverTest do
  use ExUnit.Case, async: true

  alias Hexpm.Accounts.OrganizationDomains.Resolver

  @noerror 0
  @servfail 2
  @nxdomain 3

  test "returns the TXT records, joining a record split into strings" do
    opts =
      name_server(fn query ->
        reply(query, @noerror, [
          txt([~c"v=spf1 include:example.net ~all"]),
          txt([~c"hexpm-verification=", ~c"token"])
        ])
      end)

    assert Resolver.lookup(~c"example.com", opts) == [
             "v=spf1 include:example.net ~all",
             "hexpm-verification=token"
           ]
  end

  test "returns no records when the name has no TXT records" do
    assert Resolver.lookup(~c"example.com", name_server(&reply(&1, @noerror))) == []
  end

  test "returns no records when the name does not exist" do
    assert Resolver.lookup(~c"example.com", name_server(&reply(&1, @nxdomain))) == []
  end

  test "raises when the name server fails" do
    opts = [servfail_retry_timeout: 0] ++ name_server(&reply(&1, @servfail))

    assert_raise RuntimeError, ~r/DNS lookup for example.com failed: {:servfail, /, fn ->
      Resolver.lookup(~c"example.com", opts)
    end
  end

  test "raises when there is no name server to ask" do
    assert_raise RuntimeError, "DNS lookup for example.com failed: :nxdomain", fn ->
      Resolver.lookup(~c"example.com", nameservers: [])
    end
  end

  defp name_server(answer) do
    {:ok, socket} = :gen_udp.open(0, [:binary, ip: {127, 0, 0, 1}, active: false])
    {:ok, port} = :inet.port(socket)
    start_supervised!({Task, fn -> serve(socket, answer) end})
    [nameservers: [{{127, 0, 0, 1}, port}]]
  end

  defp serve(socket, answer) do
    {:ok, {address, port, packet}} = :gen_udp.recv(socket, 0)
    {:ok, query} = :inet_dns.decode(packet)
    :ok = :gen_udp.send(socket, address, port, :inet_dns.encode(answer.(query)))
    serve(socket, answer)
  end

  defp reply(query, rcode, answers \\ []) do
    header =
      :inet_dns.make_header(:inet_dns.msg(query, :header), qr: true, ra: true, rcode: rcode)

    :inet_dns.make_msg(query, header: header, anlist: answers, arlist: [])
  end

  defp txt(strings) do
    :inet_dns.make_rr(domain: ~c"example.com", class: :in, type: :txt, ttl: 60, data: strings)
  end
end

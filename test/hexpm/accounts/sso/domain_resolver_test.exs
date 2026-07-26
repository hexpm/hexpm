defmodule Hexpm.Accounts.SSO.DomainResolverTest do
  use ExUnit.Case, async: true

  require Record

  Record.defrecordp(
    :dns_rec,
    Record.extract(:dns_rec, from_lib: "kernel/src/inet_dns.hrl")
  )

  Record.defrecordp(
    :dns_rr,
    Record.extract(:dns_rr, from_lib: "kernel/src/inet_dns.hrl")
  )

  alias Hexpm.Accounts.SSO.DomainResolver.Inet

  test "classifies missing and transient resolver failures" do
    for {response, expected} <- [
          {{:error, :nxdomain}, {:definitive, :missing}},
          {{:error, {:nxdomain, :message}}, {:definitive, :missing}},
          {{:error, :timeout}, {:transient, :timeout}},
          {{:error, :servfail}, {:transient, :servfail}},
          {{:error, {:servfail, :message}}, {:transient, :servfail}}
        ] do
      assert Inet.lookup_txt("example.com", fn _name, :in, :txt, [], 5_000 -> response end) ==
               expected
    end
  end

  test "joins TXT character strings and ignores other answer types" do
    message =
      dns_rec(
        anlist: [
          dns_rr(type: :a, data: {192, 0, 2, 1}),
          dns_rr(type: :txt, data: [~c"hexpm-sso-", ~c"verification=value"])
        ]
      )

    assert Inet.lookup_txt("example.com", fn name, class, type, options, timeout ->
             assert name == ~c"example.com"
             assert class == :in
             assert type == :txt
             assert options == []
             assert timeout == 5_000
             {:ok, message}
           end) == {:ok, ["hexpm-sso-verification=value"]}
  end

  test "classifies empty or malformed successful responses definitively" do
    assert Inet.lookup_txt("example.com", fn _name, _class, _type, _options, _timeout ->
             {:ok, dns_rec(anlist: [])}
           end) == {:definitive, :missing}

    assert Inet.lookup_txt("example.com", fn _name, _class, _type, _options, _timeout ->
             {:ok, dns_rec(anlist: [:malformed])}
           end) == {:definitive, :malformed}

    assert Inet.lookup_txt("example.com", fn _name, _class, _type, _options, _timeout ->
             {:ok, :malformed}
           end) == {:definitive, :malformed}
  end

  test "contains resolver exceptions as transient failures" do
    assert Inet.lookup_txt("example.com", fn _name, _class, _type, _options, _timeout ->
             raise "resolver failed"
           end) == {:transient, :resolver_failure}
  end
end

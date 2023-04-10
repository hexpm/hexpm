defmodule Hexpm.CDN.FastlyTest do
  use ExUnit.Case, async: true
  import Mox
  alias Hexpm.CDN.Fastly

  describe "purge_key/2" do
    test "calls purge endpoint 3 times after waiting" do
      expect(Hexpm.HTTP.Mock, :post, 3, fn url, headers, body ->
        assert url == "https://api.fastly.com/service/fastly_hexrepo/purge"
        assert body == %{"surrogate_keys" => ["key1", "key2"]}

        assert headers == [
                 {"fastly-key", "fastly_key"},
                 {"accept", "application/json"},
                 {"content-type", "application/json"}
               ]

        {:ok, 200, [], ""}
      end)

      assert Fastly.purge_key(:fastly_hexrepo, ["key1", "key2"]) == :ok
      Process.sleep(300)
    end
  end

  describe "public_ips/0" do
    test "returns IPs" do
      expect(Hexpm.HTTP.Mock, :get, fn url, headers ->
        assert url == "https://api.fastly.com/public-ip-list"

        assert headers == [
                 {"fastly-key", "fastly_key"},
                 {"accept", "application/json"}
               ]

        {:ok, 200, [], %{"addresses" => ["1.2.3.4", "1.2.3.4/32", "1.2.3.4/16"]}}
      end)

      assert Fastly.public_ips() == [
               {<<1, 2, 3, 4>>, 32},
               {<<1, 2, 3, 4>>, 32},
               {<<1, 2, 3, 4>>, 16}
             ]
    end
  end
end

defmodule Hexpm.CDN.FastlyTest do
  use ExUnit.Case, async: true
  import Mox
  alias Hexpm.CDN.Fastly

  setup :verify_on_exit!

  describe "purge_key/2" do
    test "sends one purge request for the keys" do
      expect(Hexpm.HTTP.Mock, :post, fn url, headers, body ->
        assert url == "https://api.fastly.com/service/fastly_hexrepo/purge"
        assert body == %{"surrogate_keys" => ["key1", "key2"]}

        assert headers == [
                 {"fastly-key", "fastly_key"},
                 {"accept", "application/json"},
                 {"content-type", "application/json"}
               ]

        {:ok, 200, [], %{"key1" => "1-1", "key2" => "1-2"}}
      end)

      assert Fastly.purge_key(:fastly_hexrepo, ["key1", "key2"]) == :ok
    end

    test "uses the docs credential for docs services" do
      expect(Hexpm.HTTP.Mock, :post, fn url, headers, _body ->
        assert url == "https://api.fastly.com/service/fastly_hexdocs/purge"
        assert {"fastly-key", "fastly_docs_key"} in headers
        {:ok, 200, [], ""}
      end)

      assert Fastly.purge_key(:fastly_hexdocs, ["docs-key"]) == :ok
    end

    @tag :capture_log
    test "retries 5xx and 429 before giving up with the status and body" do
      expect(Hexpm.HTTP.Mock, :post, 5, fn _url, _headers, _body ->
        {:ok, 503, [], %{"msg" => "unavailable"}}
      end)

      assert Fastly.purge_key(:fastly_hexrepo, ["key"]) ==
               {:error, {:status, 503, %{"msg" => "unavailable"}}}
    end

    @tag :capture_log
    test "returns the transport error after retries" do
      expect(Hexpm.HTTP.Mock, :post, 5, fn _url, _headers, _body -> {:error, :closed} end)

      assert Fastly.purge_key(:fastly_hexrepo, ["key"]) == {:error, :closed}
    end

    test "emits a purge_request event with the status" do
      :telemetry.attach(
        "purge-request-#{inspect(self())}",
        [:hexpm, :cdn, :purge_request, :stop],
        fn _event, _measurements, metadata, pid -> send(pid, {:purge_request, metadata}) end,
        self()
      )

      expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body -> {:ok, 200, [], ""} end)
      assert Fastly.purge_key(:fastly_hexrepo, ["key"]) == :ok

      assert_receive {:purge_request, %{service: :fastly_hexrepo, keys: ["key"], status: 200}}
    end
  end

  describe "verify/2" do
    test "checks every target at the nearest POP and every probed POP, batched" do
      expect(Hexpm.HTTP.Mock, :head, 4, fn url, headers, _opts ->
        assert url in ["https://repo.example/packages/foo", "https://repo.example/packages/bar"]

        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> assert headers == []
          {_, "nrt-tokyo-jp"} -> assert {"fastly-key", "fastly_key"} in headers
        end

        {:ok, 200, [{"ETag", ~s("abc")}], ""}
      end)

      foo = %{url: "https://repo.example/packages/foo", etag: ~s("abc")}
      bar = %{url: "https://repo.example/packages/bar", etag: ~s("abc")}

      assert Fastly.verify(:fastly_hexrepo, [foo, bar]) |> Enum.sort() ==
               Enum.sort([{foo, :ok}, {bar, :ok}])
    end

    test "probes no POPs for the docs services" do
      expect(Hexpm.HTTP.Mock, :head, fn "https://hexdocs.example/foo/index.html", [], _opts ->
        {:ok, 200, [{"etag", ~s("abc")}], ""}
      end)

      target = %{url: "https://hexdocs.example/foo/index.html", etag: "abc"}
      assert Fastly.verify(:fastly_hexdocs, [target]) == [{target, :ok}]
    end

    test "fetches a private repository's object with a repository token, probes included" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn url, headers, _opts ->
        assert url == "https://repo.example/repos/acme/packages/foo"
        assert {"authorization", "Bearer " <> token} = List.keyfind(headers, "authorization", 0)

        assert {:ok, %{"scope" => "repository:acme", "sub" => "system:cdn-verify"}} =
                 Hexpm.OAuth.JWT.verify_and_decode(token)

        {:ok, 200, [{"etag", ~s("abc")}], ""}
      end)

      target = %{
        url: "https://repo.example/repos/acme/packages/foo",
        etag: "abc",
        repository: "acme"
      }

      assert Fastly.verify(:fastly_hexrepo, [target]) == [{target, :ok}]
    end

    test "reports every POP still serving the old object with the caches that served it" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil ->
            {:ok, 200, [{"etag", ~s("abc")}, {"x-cache-served-by", "cache-iad-1-IAD"}], ""}

          {_, "nrt-tokyo-jp"} ->
            {:ok, 200,
             [
               {"etag", ~s("old")},
               {"x-cache-served-by", "cache-iad-2-IAD, cache-nrt-1-NRT"},
               {"x-cache", "HIT, HIT"},
               {"x-cache-age", "120, 3"},
               {"x-cache-hits", "5, 1"}
             ], ""}
        end
      end)

      target = %{url: "https://repo.example/packages/foo", etag: "abc"}

      assert Fastly.verify(:fastly_hexrepo, [target]) ==
               [
                 {target,
                  {:error,
                   {:stale,
                    [
                      %{
                        pop: "nrt-tokyo-jp",
                        served: {:etag, ~s("old")},
                        cache:
                          "x-cache-served-by: cache-iad-2-IAD, cache-nrt-1-NRT; " <>
                            "x-cache: HIT, HIT; x-cache-age: 120, 3; x-cache-hits: 5, 1"
                      }
                    ]}}}
               ]
    end

    test "passes a copy whose write number is at or past the target's" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> {:ok, 200, [{"etag", ~s("later")}, {"x-cache-write", "8"}], ""}
          _probe -> {:ok, 200, [{"etag", ~s("abc")}, {"x-cache-write", "7"}], ""}
        end
      end)

      target = %{url: "https://repo.example/packages/foo", etag: ~s("abc"), write: 7}
      assert Fastly.verify(:fastly_hexrepo, [target]) == [{target, :ok}]
    end

    test "reports a copy with a lower write number as stale whatever its ETag" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> {:ok, 200, [{"etag", ~s("abc")}, {"x-cache-write", "7"}], ""}
          _probe -> {:ok, 200, [{"etag", ~s("abc")}, {"x-cache-write", "6"}], ""}
        end
      end)

      target = %{url: "https://repo.example/packages/foo", etag: ~s("abc"), write: 7}

      assert Fastly.verify(:fastly_hexrepo, [target]) ==
               [
                 {target,
                  {:error, {:stale, [%{pop: "nrt-tokyo-jp", served: {:write, 6}, cache: nil}]}}}
               ]
    end

    test "compares the ETag when the copy carries no write number" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> {:ok, 200, [{"etag", ~s("abc")}], ""}
          _probe -> {:ok, 200, [{"etag", ~s("old")}], ""}
        end
      end)

      target = %{url: "https://repo.example/packages/foo", etag: ~s("abc"), write: 7}

      assert Fastly.verify(:fastly_hexrepo, [target]) ==
               [
                 {target,
                  {:error,
                   {:stale, [%{pop: "nrt-tokyo-jp", served: {:etag, ~s("old")}, cache: nil}]}}}
               ]
    end

    test "accepts a deleted object re-created by a later write" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, _headers, _opts ->
        {:ok, 200, [{"etag", ~s("new")}, {"x-cache-write", "10"}], ""}
      end)

      target = %{url: "https://repo.example/tarballs/foo-1.0.0.tar", etag: nil, write: 9}
      assert Fastly.verify(:fastly_hexrepo, [target]) == [{target, :ok}]
    end

    test "reports a deleted object still served as stale" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> {:ok, 200, [{"etag", ~s("old")}, {"x-cache-write", "9"}], ""}
          _probe -> {:ok, 200, [{"etag", ~s("old")}], ""}
        end
      end)

      target = %{url: "https://repo.example/tarballs/foo-1.0.0.tar", etag: nil, write: 9}

      assert Fastly.verify(:fastly_hexrepo, [target]) ==
               [
                 {target,
                  {:error,
                   {:stale,
                    [
                      %{pop: :nearest, served: {:write, 9}, cache: nil},
                      %{pop: "nrt-tokyo-jp", served: {:write, nil}, cache: nil}
                    ]}}}
               ]
    end

    test "a probe that fails does not fail the check" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> {:ok, 200, [{"etag", ~s("abc")}], ""}
          _probe -> {:error, :timeout}
        end
      end)

      target = %{url: "https://repo.example/packages/foo", etag: "abc"}
      assert Fastly.verify(:fastly_hexrepo, [target]) == [{target, :ok}]
    end

    test "expects a 404 for a deleted object" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, _headers, _opts -> {:ok, 404, [], ""} end)

      target = %{url: "https://repo.example/tarballs/foo-1.0.0.tar", etag: nil}
      assert Fastly.verify(:fastly_hexrepo, [target]) == [{target, :ok}]
    end

    test "accepts the organization docs redirect for a deleted page" do
      expect(Hexpm.HTTP.Mock, :head, fn "https://foo.hexdocs.example/1.0.0/index.html",
                                        [],
                                        _opts ->
        {:ok, 301, [{"location", "http://foo.localhost:5002/1.0.0/index.html"}], ""}
      end)

      target = %{url: "https://foo.hexdocs.example/1.0.0/index.html", etag: nil}
      assert Fastly.verify(:fastly_hexdocs, [target]) == [{target, :ok}]
    end

    test "rejects any other redirect for a deleted page" do
      expect(Hexpm.HTTP.Mock, :head, fn _url, _headers, _opts ->
        {:ok, 301, [{"location", "https://foo.hexdocs.example/"}], ""}
      end)

      target = %{url: "https://foo.hexdocs.example/1.0.0/index.html", etag: nil}

      assert Fastly.verify(:fastly_hexdocs, [target]) ==
               [{target, {:error, {:status, 301, nil}}}]
    end

    test "returns the status when the nearest POP does not serve the object" do
      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> {:ok, 503, [{"x-cache-served-by", "cache-bma-1-BMA"}], ""}
          _probe -> {:ok, 200, [{"etag", ~s("abc")}], ""}
        end
      end)

      target = %{url: "https://repo.example/packages/foo", etag: "abc"}

      assert Fastly.verify(:fastly_hexrepo, [target]) ==
               [{target, {:error, {:status, 503, "x-cache-served-by: cache-bma-1-BMA"}}}]
    end

    test "emits telemetry per POP with the result" do
      :telemetry.attach(
        "verify-#{inspect(self())}",
        [:hexpm, :cdn, :verify, :stop],
        fn _event, _measurements, metadata, pid -> send(pid, {:verify, metadata}) end,
        self()
      )

      expect(Hexpm.HTTP.Mock, :head, 2, fn _url, headers, _opts ->
        case List.keyfind(headers, "hex-cache-probe", 0) do
          nil -> {:ok, 200, [{"etag", ~s("abc")}], ""}
          _probe -> {:ok, 200, [{"etag", ~s("old")}], ""}
        end
      end)

      target = %{url: "https://repo.example/packages/foo", etag: "abc"}
      assert [{^target, {:error, {:stale, _}}}] = Fastly.verify(:fastly_hexrepo, [target])

      assert_receive {:verify,
                      %{url: "https://repo.example/packages/foo", pop: :nearest, result: :ok}}

      assert_receive {:verify,
                      %{
                        url: "https://repo.example/packages/foo",
                        pop: "nrt-tokyo-jp",
                        result: :stale
                      }}
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

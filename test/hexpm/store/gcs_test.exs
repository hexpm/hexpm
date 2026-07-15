defmodule Hexpm.Store.GCSTest do
  use ExUnit.Case, async: false
  import Mox

  alias Hexpm.Store.GCS

  setup :verify_on_exit!

  setup do
    original_auth = Application.get_env(:hexpm, :gcs_auth)
    original_url = Application.get_env(:hexpm, :gcs_url)
    Application.put_env(:hexpm, :gcs_auth, {__MODULE__, :auth_headers})
    Application.put_env(:hexpm, :gcs_url, "https://storage.example")

    on_exit(fn ->
      Application.put_env(:hexpm, :gcs_auth, original_auth)
      Application.put_env(:hexpm, :gcs_url, original_url)
    end)

    :ok
  end

  def auth_headers, do: [{"authorization", "Bearer token"}]

  test "reads object bodies without decoding json" do
    expect(Hexpm.HTTP.Mock, :get, fn url, headers, opts ->
      assert url == "https://storage.example/bucket/files/package/1.0.0/data.json"
      assert headers == [{"authorization", "Bearer token"}]
      assert opts == [decode_body: false]
      {:ok, 200, [{"content-type", "application/json"}], ~s({"key":"value"})}
    end)

    assert GCS.get("bucket", "files/package/1.0.0/data.json", []) == ~s({"key":"value"})
  end

  test "returns nil only for missing objects" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, decode_body: false ->
      {:ok, 404, [], ""}
    end)

    assert GCS.get("bucket", "missing", []) == nil
  end

  test "retries transient object read failures" do
    expect(Hexpm.HTTP.Mock, :get, 2, fn _url, _headers, decode_body: false ->
      attempt = Process.get(:gcs_get_attempt, 0)
      Process.put(:gcs_get_attempt, attempt + 1)

      if attempt == 0 do
        {:ok, 503, [], "unavailable"}
      else
        {:ok, 200, [], "contents"}
      end
    end)

    assert GCS.get("bucket", "file", []) == "contents"
  end

  test "raises for terminal object read failures" do
    expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, decode_body: false ->
      {:ok, 403, [], "forbidden"}
    end)

    assert_raise RuntimeError,
                 "GCS GET https://storage.example/bucket/file returned status 403",
                 fn ->
                   GCS.get("bucket", "file", [])
                 end
  end

  @tag :tmp_dir
  test "streams files to encoded object paths while preserving slashes", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "upload")
    File.write!(path, "streamed")

    expect(Hexpm.HTTP.Mock, :put_file, fn url, headers, ^path, [] ->
      assert url == "https://storage.example/bucket/docs/a%20b%3F%23.html"
      assert {"authorization", "Bearer token"} in headers
      assert {"x-goog-meta-surrogate-key", "docs"} in headers
      assert {"cache-control", "public, max-age=3600"} in headers
      assert {"content-type", "text/html"} in headers
      {:ok, 200, [], ""}
    end)

    assert :ok =
             GCS.put_file("bucket", "docs/a b?#.html", path,
               meta: [{"surrogate-key", "docs"}],
               cache_control: "public, max-age=3600",
               content_type: "text/html"
             )
  end

  test "treats missing objects as successfully deleted" do
    expect(Hexpm.HTTP.Mock, :delete, fn url, headers ->
      assert url == "https://storage.example/bucket/docs/missing.html"
      assert headers == [{"authorization", "Bearer token"}]
      {:ok, 404, [], ""}
    end)

    assert :ok = GCS.delete("bucket", "docs/missing.html")
  end

  test "reads object sizes without downloading contents" do
    expect(Hexpm.HTTP.Mock, :head, fn url, headers ->
      assert url == "https://storage.example/bucket/docs/file.html"
      assert headers == [{"authorization", "Bearer token"}]
      {:ok, 200, [{"content-length", "1234"}], ""}
    end)

    assert GCS.size("bucket", "docs/file.html") == 1234
  end

  test "returns nil for missing object sizes" do
    expect(Hexpm.HTTP.Mock, :head, fn _url, _headers ->
      {:ok, 404, [], ""}
    end)

    assert GCS.size("bucket", "missing") == nil
  end
end

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
end

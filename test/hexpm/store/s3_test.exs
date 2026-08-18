defmodule Hexpm.Store.S3Test do
  use ExUnit.Case, async: false

  alias Hexpm.Store.S3

  # An ExAws HTTP client that answers the requests S3.put and S3.put_file
  # make, the way S3 does: a PUT gets its ETag in a header, a multipart
  # upload gets it in the CompleteMultipartUpload body.
  defmodule FakeClient do
    @behaviour ExAws.Request.HttpClient

    @impl true
    def request(method, url, body, _headers, _opts) do
      send(self(), {:s3, method, url, body})
      {:ok, respond(method, URI.parse(url))}
    end

    defp respond(:put, %URI{query: nil}) do
      %{status_code: 200, headers: [{"ETag", ~s("9a0364b9e99bb480dd25e1f0284c8555")}]}
    end

    defp respond(:post, %URI{query: "uploads=1"}) do
      %{
        status_code: 200,
        headers: [],
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>upload-1</UploadId></InitiateMultipartUploadResult>
        """
      }
    end

    defp respond(:put, %URI{query: "partNumber=" <> _}) do
      %{status_code: 200, headers: [{"ETag", ~s("part")}]}
    end

    defp respond(:post, %URI{query: "uploadId=" <> _}) do
      %{
        status_code: 200,
        headers: [],
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <CompleteMultipartUploadResult><Location>l</Location><Bucket>b</Bucket><Key>k</Key><ETag>&quot;3858f62230ac3c915f300c664312c11f-2&quot;</ETag></CompleteMultipartUploadResult>
        """
      }
    end
  end

  setup do
    overrides = [http_client: FakeClient, access_key_id: "key", secret_access_key: "secret"]
    previous = Enum.map(overrides, fn {key, _} -> {key, Application.get_env(:ex_aws, key)} end)
    Enum.each(overrides, fn {key, value} -> Application.put_env(:ex_aws, key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:ex_aws, key, value) end)
    end)

    :ok
  end

  test "put returns the ETag from the response header" do
    assert S3.put("us-east-1,bucket", "packages/foo", "body", []) ==
             {:ok, %{etag: ~s("9a0364b9e99bb480dd25e1f0284c8555")}}

    assert_received {:s3, :put, "https://s3.amazonaws.com/bucket/packages/foo", "body"}
  end

  test "put_file returns the ETag from the multipart completion" do
    path = Path.join(System.tmp_dir!(), "hexpm-s3-test-#{System.unique_integer([:positive])}")
    File.write!(path, "tarball")
    on_exit(fn -> File.rm(path) end)

    assert S3.put_file("us-east-1,bucket", "tarballs/foo-1.0.0.tar", path, []) ==
             {:ok, %{etag: ~s("3858f62230ac3c915f300c664312c11f-2")}}

    assert_received {:s3, :post,
                     "https://s3.amazonaws.com/bucket/tarballs/foo-1.0.0.tar?uploadId=upload-1",
                     _}
  end
end

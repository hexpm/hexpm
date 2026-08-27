defmodule Hexpm.Store.S3Test do
  use ExUnit.Case, async: false

  alias Hexpm.Store.S3

  # An ExAws HTTP client that answers the requests S3.put and S3.put_file
  # make, the way S3 does: a PUT gets its ETag in a header, a multipart
  # upload gets it in the CompleteMultipartUpload body.
  defmodule FakeClient do
    @behaviour ExAws.Request.HttpClient

    @object "logs/day.log.gz"

    # Two full 1 MiB download parts and a 4-byte tail.
    def object_body, do: String.duplicate("0123456789abcdef", 131_072) <> "tail"

    @impl true
    def request(method, url, body, headers, _opts) do
      send(self(), {:s3, method, url, body})
      {:ok, respond(method, URI.parse(url), headers)}
    end

    defp respond(:head, %URI{path: "/bucket/" <> @object}, _headers) do
      %{
        status_code: 200,
        headers: [{"Content-Length", Integer.to_string(byte_size(object_body()))}]
      }
    end

    defp respond(:head, %URI{}, _headers) do
      %{status_code: 404, headers: [], body: ""}
    end

    defp respond(:get, %URI{path: "/bucket/" <> @object}, headers) do
      "bytes=" <> range =
        Enum.find_value(headers, fn {key, value} ->
          if String.downcase(to_string(key)) == "range", do: value
        end)

      [first, last] = range |> String.split("-") |> Enum.map(&String.to_integer/1)
      %{status_code: 200, headers: [], body: binary_part(object_body(), first, last - first + 1)}
    end

    defp respond(method, uri, _headers), do: respond(method, uri)

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

  test "stream returns the object body in ranged chunks and nil for a missing object" do
    chunks = S3.stream("us-east-1,bucket", "logs/day.log.gz") |> Enum.to_list()

    assert Enum.map(chunks, &byte_size/1) == [1_048_576, 1_048_576, 4]
    assert IO.iodata_to_binary(chunks) == FakeClient.object_body()
    assert S3.stream("us-east-1,bucket", "logs/missing.log.gz") == nil
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

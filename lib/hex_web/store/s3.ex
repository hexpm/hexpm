defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store
  alias ExAws.S3

  def list_logs(prefix) do
    list(:logs_bucket, prefix)
  end

  def get_logs(key) do
    Application.get_env(:hex_web, :logs_bucket)
    |> S3.get_object!(key)
    |> Map.get(:body)
  end

  def put_logs(key, blob) do
    Application.get_env(:hex_web, :logs_bucket)
    |> S3.put_object!(key, blob)
  end

  def put_registry(data) do
    upload(:s3_bucket, "registry.ets.gz", [], :zlib.gzip(data))
  end

  def send_registry(conn) do
    redirect(conn, :cdn_url, "registry.ets.gz")
  end

  def put_release(name, data) do
    upload(:s3_bucket, Path.join("tarballs", name), [], data)
  end

  def delete_release(name) do
    path = Path.join("tarballs", name)
    delete(:s3_bucket, path)
  end

  def send_release(conn, name) do
    path = Path.join("tarballs", name)
    redirect(conn, :cdn_url, path)
  end

  def put_docs(name, data) do
    path = Path.join("docs", name)
    upload(:s3_bucket, path, [], data)
  end

  def delete_docs(name) do
    path = Path.join("docs", name)
    delete(:s3_bucket, path)
  end

  def send_docs(conn, name) do
    path = Path.join("docs", name)
    redirect(conn, :cdn_url, path)
  end

  def put_docs_page(path, data) do
    opts = case Path.extname(path) do
      "." <> ext ->
        mime = Plug.MIME.type(ext)
        headers = ["content-type": mime]
      "" ->
        headers = []
    end
    |> Keyword.put(:cache_control, "public, max-age=1800")

    headers = Keyword.put(headers, :"cache-control", "public, max-age=1800")

    upload(:docs_bucket, path, headers, data)
  end

  def list_docs_pages(path) do
    list(:docs_bucket, path)
  end

  def delete_docs_page(path) do
    delete(:docs_bucket, path)
  end

  def send_docs_page(conn, path) do
    redirect(conn, :docs_url, path)
  end

  defp delete(bucket, path) do
    bucket = Application.get_env(:hex_web, bucket)
    S3.delete_object!(bucket, path)
  end

  defp redirect(conn, location, path) do
    url = Application.get_env(:hex_web, location) <> "/" <> path
    HexWeb.Plug.redirect(conn, url)
  end

  def upload(bucket, path, data, opts \\ []) do
    opts = Keyword.put(opts, :acl, :public_read)
    # TODO: cache
    bucket  = Application.get_env(:hex_web, bucket)
    S3.put_object(bucket, path, data, acl: "public-read")
  end

  defp list(bucket, prefix) do
    bucket = Application.get_env(:hex_web, bucket)
    list_all(bucket, prefix, nil, [])
  end

  defp list_all(bucket, prefix, marker, keys) do
    opts = [prefix: prefix]
    if marker do
      opts = Keyword.put(opts, :marker, marker)
    end

    {:ok, %{body: result}} = S3.list_objects(bucket, opts)

    new_keys = result.contents |> Enum.map(&Dict.get(&1, :key))
    all_keys = new_keys ++ keys

    if result.is_truncated == "true" do
      list_all(bucket, prefix, List.last(new_keys), all_keys)
    else
      all_keys
    end
  end
end

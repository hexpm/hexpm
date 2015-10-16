defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store
  alias ExAws.S3
  alias ExAws.S3.Impl, as: S3Impl

  def list_logs(region, bucket, prefix) do
    list(region, bucket, prefix)
  end

  def get_logs(region, bucket, key) do
    S3.new(region: region)
    |> S3Impl.get_object!(bucket, key)
    |> Map.get(:body)
  end

  def put_logs(region, bucket, key, blob) do
    S3.new(region: region)
    |> S3Impl.put_object!(bucket, key, blob)
  end

  def put_registry(data) do
    upload(:s3_bucket, "registry.ets.gz", :zlib.gzip(data))
  end

  def send_registry(conn) do
    redirect(conn, :cdn_url, "registry.ets.gz")
  end

  def put_release(name, data) do
    upload(:s3_bucket, Path.join("tarballs", name), data)
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
    upload(:s3_bucket, path, data)
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
      "." <> ext -> [content_type: Plug.MIME.type(ext)]
      ""         -> []
    end
    |> Keyword.put(:cache_control, "public, max-age=1800")

    upload(:docs_bucket, path, data, opts)
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
    Application.get_env(:hex_web, bucket)
    |> S3.put_object!(path, data, opts)
  end

  defp list(region, bucket, prefix) do
    S3.new(region: region)
    |> S3Impl.stream_objects!(bucket, prefix: prefix)
    |> Stream.map(&Map.get(&1, :key))
  end

  defp list(bucket, prefix) do
    Application.get_env(:hex_web, bucket)
    |> S3.stream_objects!(prefix: prefix)
    |> Stream.map(&Map.get(&1, :key))
  end
end

defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store

  alias ExAws.S3
  alias ExAws.S3.Impl, as: S3Impl

  def list_logs(region, bucket, prefix) do
    list(region, bucket, prefix)
  end

  def get_logs(nil, bucket, key) do
    S3.get_object!(bucket, key)
    |> Map.get(:body)
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

  def put_registry(data, signature) do
    meta = [{"surrogate-key", "registry"}]
    meta = if signature, do: [{"signature", signature}|meta], else: meta

    opts = [cache_control: "public, max-age=600", meta: meta]
    upload(:s3_bucket, "registry.ets.gz", data, opts)
  end

  def put_registry_signature(signature) do
    opts = [cache_control: "public, max-age=600", meta: [{"surrogate-key", "registry"}]]
    upload(:s3_bucket, "registry.ets.gz.signed", signature, opts)
  end

  def send_registry(conn) do
    redirect(conn, :cdn_url, "registry.ets.gz")
  end

  def send_registry_signature(conn) do
    redirect(conn, :cdn_url, "registry.ets.gz.signed")
  end

  def put_release(package, version, data) do
    name = "#{package}-#{version}.tar"
    key  = "tarballs/#{package}-#{version}"
    opts = [cache_control: "public, max-age=604800", meta: [{"surrogate-key", key}]]
    upload(:s3_bucket, Path.join("tarballs", name), data, opts)
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

  def put_docs_file(path, data) do
    opts = case Path.extname(path) do
      "." <> ext -> [content_type: Plug.MIME.type(ext)]
      ""         -> []
    end

    upload(:docs_bucket, path, data, opts)
  end

  def put_docs_page(path, key, data) do
    opts = case Path.extname(path) do
      "." <> ext -> [content_type: Plug.MIME.type(ext)]
      ""         -> []
    end
    |> Keyword.put(:cache_control, "public, max-age=604800")
    |> Keyword.put(:meta, [{"surrogate-key", key}])

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
    Application.get_env(:hex_web, bucket)
    |> S3.delete_object!(path)
  end

  defp redirect(conn, location, path) do
    url = Application.get_env(:hex_web, location) <> "/" <> path
    Phoenix.Controller.redirect(conn, external: url)
  end

  def upload(bucket, path, data, opts \\ []) do
    opts = Keyword.put(opts, :acl, :public_read)
    # TODO: cache
    Application.get_env(:hex_web, bucket)
    |> S3.put_object!(path, data, opts)
  end

  defp list(nil, bucket, prefix), do: list(bucket, prefix)
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

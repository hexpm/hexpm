defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store
  alias ExAws.S3

  def list_logs(prefix) do
    list(:logs_bucket, prefix)
  end

  def get_logs(key) do
    bucket = Application.get_env(:hex_web, :logs_bucket)
    result = S3.get_object(bucket, key)
    result[:content]
  end

  def put_logs(key, blob) do
    bucket = Application.get_env(:hex_web, :logs_bucket)
    S3.put_object(bucket, key, blob)
  end

  def put_registry(data) do
    upload(:s3_bucket, "registry.ets.gz", %{}, :zlib.gzip(data))
  end

  def send_registry(conn) do
    redirect(conn, :cdn_url, "registry.ets.gz")
  end

  def put_release(name, data) do
    upload(:s3_bucket, Path.join("tarballs", name), %{}, data)
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
    upload(:s3_bucket, path, %{}, data)
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
    case Path.extname(path) do
      "." <> ext ->
        mime = Plug.MIME.type(ext)
        headers = %{"Content-Type" => mime}
      "" ->
        headers = %{}
    end

    headers = Dict.put(headers, "cache-control", "public, max-age=1800")

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
    S3.delete_object(bucket, path)
  end

  defp redirect(conn, location, path) do
    url = Application.get_env(:hex_web, location) <> "/" <> path
    HexWeb.Plug.redirect(conn, url)
  end

  def upload(bucket, path, headers, data) do
    # TODO: cache
    bucket     = Application.get_env(:hex_web, bucket)
    S3.put_object(bucket, path, data, headers)
    S3.put_object_acl(bucket, path, %{acl: :public_read})
  end

  defp list(bucket, prefix) do
    bucket = Application.get_env(:hex_web, bucket)
    list_all(bucket, prefix, nil, %{})
  end

  defp list_all(bucket, prefix, marker, keys) do
    opts = %{"prefix" => prefix}
    if marker do
      opts = Dict.put(opts, "marker", marker)
    end

    result = S3.list_objects(bucket, opts)

    new_keys = result[:contents]
    all_keys = new_keys ++ keys

    if result[:is_truncated] do
      list_all(bucket, prefix, List.last(new_keys), all_keys)
    else
      all_keys
    end
  end
end

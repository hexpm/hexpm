defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store

  defmacrop s3_config(opts) do
    quote do
      {:config,
        unquote(opts[:url]),
        unquote(opts[:access_key_id]),
        unquote(opts[:secret_access_key]),
        :virtual_hosted}
    end
  end

  def list_logs(prefix) do
    list(:logs_bucket, prefix)
  end

  def get_logs(key) do
    bucket = Application.get_env(:hex_web, :logs_bucket) |> String.to_char_list
    key = String.to_char_list(key)
    result = :mini_s3.get_object(bucket, key, [], config())
    result[:content]
  end

  def put_logs(key, blob) do
    bucket = Application.get_env(:hex_web, :logs_bucket) |> String.to_char_list
    key = String.to_char_list(key)
    :mini_s3.put_object(bucket, key, blob, [], [], config())
  end

  def put_registry(data) do
    upload(:s3_bucket, 'registry.ets.gz', [], :zlib.gzip(data))
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
    case Path.extname(path) do
      "." <> ext ->
        mime = Plug.MIME.type(ext)
        headers = [{'content-type', String.to_char_list(mime)}]
      "" ->
        headers = []
    end

    headers = headers ++ [{'cache-control', 'public, max-age=1800'}]

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
    bucket = Application.get_env(:hex_web, bucket) |> String.to_char_list
    path = String.to_char_list(path)
    :mini_s3.delete_object(bucket, path, config())
  end

  defp redirect(conn, location, path) do
    url = Application.get_env(:hex_web, location) <> "/" <> path
    HexWeb.Plug.redirect(conn, url)
  end

  def upload(bucket, path, headers, data) when is_binary(path),
    do: upload(bucket, String.to_char_list(path), headers, data)

  def upload(bucket, path, headers, data) when is_list(path) do
    # TODO: cache
    bucket     = Application.get_env(:hex_web, bucket) |> String.to_char_list
    opts       = [acl: :public_read]
    :mini_s3.put_object(bucket, path, data, opts, headers, config())
  end

  defp list(bucket, prefix) do
    prefix = String.to_char_list(prefix)
    bucket = Application.get_env(:hex_web, bucket) |> String.to_char_list
    list_all(bucket, prefix, nil, [])
  end

  defp list_all(bucket, prefix, marker, keys) do
    opts = [prefix: prefix]
    if marker do
      opts = opts ++ [marker: String.to_char_list(marker)]
    end

    result = :mini_s3.list_objects(bucket, opts, config())
    new_keys = Enum.map(result[:contents], &List.to_string(&1[:key]))
    all_keys = new_keys ++ keys

    if result[:is_truncated] do
      list_all(bucket, prefix, List.last(new_keys), all_keys)
    else
      all_keys
    end
  end

  defp config do
    access_key = Application.get_env(:hex_web, :s3_access_key) |> String.to_char_list
    secret_key = Application.get_env(:hex_web, :s3_secret_key) |> String.to_char_list
    url = Application.get_env(:hex_web, :s3_url) |> String.to_char_list
    s3_config(access_key_id: access_key, secret_access_key: secret_key, url: url)
  end
end

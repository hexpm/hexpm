defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store

  # defrecordp :s3_config, :config, Record.extract(:config, from_lib: "mini_s3/src/internal.hrl")

  defmacrop s3_config(opts) do
    quote do
      { :config,
        'http://s3.amazonaws.com',
        unquote(opts[:access_key_id]),
        unquote(opts[:secret_access_key]),
        :virtual_hosted }
    end
  end

  import Plug.Connection

  def put_registry(data) do
    upload('registry.ets.gz', :zlib.gzip(data))
  end

  def registry(conn) do
    redirect(conn, "registry.ets.gz")
  end

  def put_tar(name, data) do
    upload(Path.join("tarballs", name), data)
  end

  def delete_tar(name) do
    bucket     = HexWeb.Config.s3_bucket     |> String.to_char_list!
    access_key = HexWeb.Config.s3_access_key |> String.to_char_list!
    secret_key = HexWeb.Config.s3_secret_key |> String.to_char_list!
    config     = s3_config(access_key_id: access_key, secret_access_key: secret_key)

    :mini_s3.delete_object(bucket, name, config)
  end

  def tar(conn, name) do
    redirect(conn, Path.join("tarballs", name))
  end

  defp redirect(conn, path) do
    url = HexWeb.Config.cdn_url <> "/" <> path
    conn
    |> put_resp_header("location", url)
    |> send_resp(302, "")
  end

  defp upload(name, data) when is_binary(name),
    do: upload(String.to_char_list!(name), data)

  defp upload(name, data) when is_list(name) do
    bucket     = HexWeb.Config.s3_bucket     |> String.to_char_list!
    access_key = HexWeb.Config.s3_access_key |> String.to_char_list!
    secret_key = HexWeb.Config.s3_secret_key |> String.to_char_list!
    config     = s3_config(access_key_id: access_key, secret_access_key: secret_key)
    opts       = [acl: :public_read]
    headers    = []

    # TODO: cache

    :mini_s3.put_object(bucket, name, data, opts, headers, config)
  end
end

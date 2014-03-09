defmodule HexWeb.Store.S3 do
  @behaviour HexWeb.Store

  defrecordp :s3_config, :config, Record.extract(:config, from: "deps/mini_s3/src/internal.hrl")

  import Plug.Connection

  def upload_registry(file) do
    bucket     = HexWeb.Config.s3_bucket     |> String.to_char_list!
    access_key = HexWeb.Config.s3_access_key |> String.to_char_list!
    secret_key = HexWeb.Config.s3_secret_key |> String.to_char_list!
    config = s3_config(access_key_id: access_key, secret_access_key: secret_key)
    opts = [acl: :public_read]
    headers = []

    # TODO: cache

    :mini_s3.put_object(bucket, 'registry.ets', File.read!(file),
                        opts, headers, config)
  end

  def registry(conn) do
    url = HexWeb.Config.cdn_url <> "/registry.ets"

    conn
    |> put_resp_header("location", url)
    |> send_resp(302, "")
  end
end

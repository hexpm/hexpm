defmodule HexWeb.CDN do
  @type service :: atom
  @type key :: String.t
  @type ip :: <<_::32>>
  @type mask :: 0..32

  @callback purge_key(service, key | [key]) :: :ok
  @callback public_ips() :: [{ip, mask}]

  @cdn_impl Application.get_env(:hex_web, :cdn_impl)

  defdelegate purge_key(service, key), to: @cdn_impl
  defdelegate public_ips(), to: @cdn_impl
end

defmodule HexWeb.CDN do
  import HexWeb.Utils, only: [defdispatch: 2]

  @type service :: atom
  @type key :: String.t
  @type ip :: <<_::32>>
  @type mask :: 0..32

  @callback purge_key(service, key) :: :ok
  @callback public_ips() :: [{ip, mask}]

  defdispatch purge_key(service, key), to: impl
  defdispatch public_ips(), to: impl

  defp impl, do: Application.get_env(:hex_web, :cdn_impl)
end

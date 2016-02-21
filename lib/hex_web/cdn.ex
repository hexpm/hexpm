defmodule HexWeb.CDN do
  import HexWeb.Utils, only: [defdispatch: 2]

  @type service :: atom
  @type key :: String.t

  @callback purge_key(service, key) :: :ok

  defdispatch purge_key(service, key), to: impl

  defp impl, do: Application.get_env(:hex_web, :cdn_impl)
end

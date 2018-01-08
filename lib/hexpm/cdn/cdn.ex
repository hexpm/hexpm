defmodule Hexpm.CDN do
  @type service :: atom
  @type key :: String.t()
  @type ip :: <<_::32>>
  @type mask :: 0..32

  @callback purge_key(service, key | [key]) :: :ok
  @callback public_ips() :: [{ip, mask}]

  defp impl(), do: Application.get_env(:hexpm, :cdn_impl)

  def purge_key(service, key), do: impl().purge_key(service, key)
  def public_ips(), do: impl().public_ips()
end

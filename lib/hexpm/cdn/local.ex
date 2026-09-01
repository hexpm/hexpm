defmodule Hexpm.CDN.Local do
  @behaviour Hexpm.CDN

  def purge_key(_service, _keys), do: :ok
  def verify(_service, targets), do: Enum.map(targets, &{&1, :ok})
  def public_ips, do: [{<<127, 0, 0, 0>>, 24}]
end

defmodule HexWeb.CDN.Local do
  @behaviour HexWeb.CDN

  def purge_key(_service, _key), do: :ok
end

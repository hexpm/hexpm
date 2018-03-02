defmodule Hexpm.Web.ReleaseTar do
  def metadata(tarball) do
    case :hex_tarball.unpack(tarball, :memory) do
      {:ok, %{checksum: checksum, metadata: metadata}} ->
        {:ok, metadata, checksum}

      {:error, reason} ->
        {:error, List.to_string(:hex_tarball.format_error(reason))}
    end
  end
end

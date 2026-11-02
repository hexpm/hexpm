defmodule HexpmWeb.API.StagedReleaseView do
  use HexpmWeb, :view

  alias Hexpm.Repository.StagedRelease

  def render("show." <> _, %{staged_release: staged, status: status}) do
    %{
      name: staged.name,
      version: to_string(staged.version),
      kind: staged.kind,
      status: status,
      checksum: encode(staged.outer_checksum || staged.docs_checksum),
      approval_checksum: StagedRelease.checksum(staged),
      expires_at: staged.expires_at,
      url: ViewHelpers.url_for_staged_release(staged),
      html_url: ViewHelpers.html_url_for_staged_release(staged)
    }
  end

  defp encode(nil), do: nil
  defp encode(checksum), do: Base.encode16(checksum, case: :lower)
end

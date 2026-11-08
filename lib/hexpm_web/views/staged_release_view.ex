defmodule HexpmWeb.StagedReleaseView do
  use HexpmWeb, :view

  import HexpmWeb.Components.Badge

  # The base path depends on the kind, so `~p` can't verify these.
  def action_path(staged, action),
    do: "#{ViewHelpers.path_for_staged_release(staged)}/#{action}"

  def approval_blocker_message(:role, staged),
    do: "Approving requires the write or admin role in #{staged.repository.organization.name}."

  def approval_blocker_message(:tfa, _staged),
    do: "Enable two-factor authentication under Security to approve this release."

  def approval_blocker_message(:email, _staged),
    do: "Verify your primary email address to approve this release."

  def approval_blocker_message(:billing, staged),
    do:
      "#{staged.repository.organization.name} has no active billing subscription, so its releases can't be approved."

  def content_label(%{kind: "docs"}), do: "Documentation"

  def content_label(%{docs_storage_key: key}) when not is_nil(key),
    do: "Release and documentation"

  def content_label(_), do: "Release"

  def dependency_entries(requirements) when is_map(requirements), do: Enum.sort(requirements)

  def dependency_entries(requirements) when is_list(requirements) do
    requirements
    |> Enum.map(&{&1["name"], &1})
    |> Enum.sort()
  end

  def dependency_entries(nil), do: []
end

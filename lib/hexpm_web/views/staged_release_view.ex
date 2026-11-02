defmodule HexpmWeb.StagedReleaseView do
  use HexpmWeb, :view

  import HexpmWeb.Components.Badge

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

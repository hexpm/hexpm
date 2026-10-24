defmodule HexpmWeb.ReleaseRetirementView do
  use HexpmWeb, :view
  import HexpmWeb.Components.PackageLayout

  def reason_options do
    Enum.map(ReleaseRetirement.reasons(), &{reason_label(&1), &1})
  end

  def reason_label(reason), do: ReleaseRetirement.reason_text(reason) || "Other"

  def versions_text(1), do: "1 version"
  def versions_text(count), do: "#{count} versions"
end

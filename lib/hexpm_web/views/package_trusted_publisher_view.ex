defmodule HexpmWeb.PackageTrustedPublisherView do
  use HexpmWeb, :view
  import HexpmWeb.Components.PackageLayout
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  def environment_label(""), do: "Any"
  def environment_label(nil), do: "Any"
  def environment_label(environment), do: environment

  def packages_label(nil), do: "All packages in the repository"
  def packages_label(packages), do: Enum.join(packages, ", ")
end

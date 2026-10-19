defmodule HexpmWeb.PackageWorkloadIdentityView do
  use HexpmWeb, :view
  import HexpmWeb.Components.PackageLayout
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  def environment_label(""), do: "Any"
  def environment_label(nil), do: "Any"
  def environment_label(environment), do: environment

  def packages_label(nil), do: "All packages in the repository"
  def packages_label(packages), do: Enum.join(packages, ", ")

  # Names only this package, so an owner who isn't in the organization
  # doesn't learn which other packages the workload identity covers.
  def public_coverage_label(nil, organization, _package),
    do: "every public package #{organization.name} owns"

  def public_coverage_label(_packages, _organization, package), do: package.name
end

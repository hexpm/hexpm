defmodule HexpmWeb.PackageOwnerView do
  use HexpmWeb, :view
  import HexpmWeb.Components.PackageLayout
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  def role_label("full"), do: "Full owner"
  def role_label("maintainer"), do: "Maintainer"
  def role_label(other), do: String.capitalize(other)

  def role_badge_class("full"), do: "bg-purple-100 text-purple-700"
  def role_badge_class("maintainer"), do: "bg-blue-100 text-blue-700"
  def role_badge_class(_), do: "bg-grey-100 text-grey-600"
end

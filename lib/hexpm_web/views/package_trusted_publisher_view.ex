defmodule HexpmWeb.PackageTrustedPublisherView do
  use HexpmWeb, :view
  import HexpmWeb.Components.PackageLayout
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  def environment_label(""), do: "Any"
  def environment_label(nil), do: "Any"
  def environment_label(environment), do: environment
end

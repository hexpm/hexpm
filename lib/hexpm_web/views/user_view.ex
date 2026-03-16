defmodule HexpmWeb.UserView do
  use HexpmWeb, :view

  import HexpmWeb.Components.Chart
  import HexpmWeb.Components.Dropdown
  import HexpmWeb.Components.PackageCard
  import HexpmWeb.Components.UserProfile

  def stats_sort_label("name"), do: "By Name"
  def stats_sort_label(_), do: "Most Downloaded"
end

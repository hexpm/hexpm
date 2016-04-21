defmodule HexWeb.PackageView do
  use HexWeb.Web, :view

  def show_sort_info(nil), do: "(Sorted by name)"
  def show_sort_info("name"), do: "(Sorted by name)"
  def show_sort_info("inserted_at"), do: "(Sorted by recently created)"
  def show_sort_info("updated_at"), do: "(Sorted by recently updated)"
  def show_sort_info("downloads"), do: "(Sorted by downloads)"
  def show_sort_info(_param), do: nil
end

defmodule HexWeb.PackageView do
  use HexWeb.Web, :view

  def show_sort_info(nil), do: "(Sorted by name)"
  def show_sort_info(param) do
    available_params = %{
      "name" => "name", "inserted_at" => "recently created",
      "downloads" => "downloads", "updated_at" => "recently updated"}

    if Map.has_key?(available_params, param), do: "(Sorted by #{available_params[param]})"
  end
end

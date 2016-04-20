defmodule HexWeb.PackageView do
  use HexWeb.Web, :view

  def show_sort_info(param) do
    available_params = %{"name" => "name", "inserted_at" => "recently created", "downloads" => "downloads"}
    if Map.has_key?(available_params, param), do: "(Sorted by #{available_params[param]})"
  end
end

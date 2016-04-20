defmodule HexWeb.PageViewTest do
  use HexWeb.ConnCase, async: true

  import Phoenix.View
  alias HexWeb.PackageView

  test "show sort info" do
    assert PackageView.show_sort_info("name") == "(Sorted by name)"
    assert PackageView.show_sort_info("inserted_at") == "(Sorted by recently created)"
    assert PackageView.show_sort_info("downloads") == "(Sorted by downloads)"
  end

  test "show sort info when sort param is not available" do
    assert PackageView.show_sort_info("some param") == nil
  end
end

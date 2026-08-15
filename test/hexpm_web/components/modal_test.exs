defmodule HexpmWeb.Components.ModalTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest

  import HexpmWeb.Components.Modal

  test "remains outside its parent layout when shown" do
    html = render_component(&test_modal/1, %{})
    document = Floki.parse_document!(html)
    classes = Floki.attribute(document, "#test-modal", "class") |> List.first() |> String.split()

    assert "fixed" in classes
    assert "inset-0" in classes
    refute "relative" in classes
  end

  defp test_modal(assigns) do
    ~H"""
    <.modal id="test-modal">Modal content</.modal>
    """
  end
end

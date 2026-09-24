defmodule HexpmWeb.Components.ConfirmationModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HexpmWeb.Components.ConfirmationModal

  test "renders the title as the dialog label with dark theme text colors" do
    html =
      render_component(&ConfirmationModal.confirmation_modal/1,
        id: "reset-modal",
        title: "Reset?",
        message: "Resetting replaces the current setup.",
        confirm_action: "/reset",
        current_user: %{id: 1}
      )

    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "#reset-modal") |> LazyHTML.attribute("aria-labelledby") ==
             ["reset-modal-title"]

    title = LazyHTML.query(document, "#reset-modal-title")
    assert LazyHTML.text(title) =~ "Reset?"
    assert "dark:text-white" in classes(title)

    message = LazyHTML.query(document, "#reset-modal-content p")
    assert LazyHTML.text(message) =~ "Resetting replaces the current setup."
    assert "dark:text-grey-300" in classes(message)
  end

  defp classes(node) do
    node
    |> LazyHTML.attribute("class")
    |> List.first()
    |> String.split()
  end
end

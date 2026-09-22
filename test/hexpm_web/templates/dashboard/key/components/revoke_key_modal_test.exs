defmodule HexpmWeb.Dashboard.Key.Components.RevokeKeyModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HexpmWeb.Dashboard.Key.Components.RevokeKeyModal

  test "renders the title as the dialog label with dark theme text colors" do
    html =
      render_component(&RevokeKeyModal.revoke_key_modal/1,
        key: %{id: 1, name: "ci"},
        current_user: %{id: 1},
        delete_key_path: "/dashboard/keys"
      )

    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "#revoke-key-1") |> LazyHTML.attribute("aria-labelledby") ==
             ["revoke-key-1-title"]

    title = LazyHTML.query(document, "#revoke-key-1-title")
    assert LazyHTML.text(title) =~ "Revoke Key"
    assert "dark:text-white" in classes(title)

    paragraphs = LazyHTML.query(document, "#revoke-key-1-content p")
    assert Enum.count(paragraphs) == 2

    for paragraph <- paragraphs do
      assert "dark:text-grey-300" in classes(paragraph)
    end
  end

  defp classes(node) do
    node
    |> LazyHTML.attribute("class")
    |> List.first()
    |> String.split()
  end
end

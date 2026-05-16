defmodule HexpmWeb.PackageOwnerLive.AddOwnerTest do
  use HexpmWeb.ConnCase

  import Phoenix.LiveViewTest

  alias HexpmWeb.PackageOwnerLive.AddOwner

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, {:shared, self()})

    current_user = insert(:user)
    package = insert(:package)
    package = Hexpm.Repo.preload(package, :repository)

    session = %{
      "package_id" => package.id,
      "current_user_id" => current_user.id
    }

    %{conn: build_conn(), session: session, package: package, current_user: current_user}
  end

  test "renders the Add owner trigger button", %{conn: conn, session: session} do
    {:ok, _view, html} = live_isolated(conn, AddOwner, session: session)
    assert html =~ "Add owner"
    assert html =~ ~s(id="add-owner-modal")
  end

  test "starts with empty preview", %{conn: conn, session: session} do
    {:ok, _view, html} = live_isolated(conn, AddOwner, session: session)
    assert html =~ "Enter a Hex username to preview the user"
  end

  test "shows user preview when a matching user is found", %{conn: conn, session: session} do
    target = insert(:user, username: "preview_target", full_name: "Preview Target")

    {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

    html =
      view
      |> form("#add-owner-form", username: target.username, level: "maintainer")
      |> render_change()

    assert html =~ "preview_target"
    assert html =~ "Preview Target"
    refute html =~ "Enter a Hex username"
    refute html =~ "No user found"
  end

  test "shows not-found state for unknown usernames", %{conn: conn, session: session} do
    {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

    html =
      view
      |> form("#add-owner-form", username: "no_such_user", level: "maintainer")
      |> render_change()

    assert html =~ "No user found"
    assert html =~ "no_such_user"
  end

  test "submit button is disabled until a user is found", %{conn: conn, session: session} do
    insert(:user, username: "findable_user")

    {:ok, view, html} = live_isolated(conn, AddOwner, session: session)
    assert submit_button_disabled?(html)

    after_lookup =
      view
      |> form("#add-owner-form", username: "findable_user", level: "maintainer")
      |> render_change()

    refute submit_button_disabled?(after_lookup)
  end

  defp submit_button_disabled?(html) do
    {:ok, doc} = Floki.parse_fragment(html)

    doc
    |> Floki.find(~s(button[type="submit"]))
    |> Enum.any?(fn button -> Floki.attribute(button, "disabled") != [] end)
  end
end

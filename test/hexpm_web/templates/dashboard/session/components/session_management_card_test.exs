defmodule HexpmWeb.Dashboard.Session.Components.SessionManagementCardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias HexpmWeb.Dashboard.Session.Components.SessionManagementCard
  alias Hexpm.UserSession

  setup :verify_on_exit!

  defp session(last_use) do
    %UserSession{
      id: 1,
      type: "browser",
      name: "Firefox on macOS",
      session_token: "token",
      inserted_at: ~U[2026-05-20 12:00:00Z],
      last_use: last_use
    }
  end

  defp render_card(session) do
    render_component(&SessionManagementCard.session_management_card/1,
      sessions: [session],
      current_session_token: Base.encode64("other-token")
    )
  end

  test "renders the country name and flag when the last-use IP resolves" do
    stub(Hexpm.Geo.Mock, :lookup_country, fn "1.2.3.4" ->
      %{iso_code: "US", name: "United States"}
    end)

    html =
      render_card(
        session(%UserSession.Use{
          used_at: ~U[2026-05-20 12:00:00.000000Z],
          ip: "1.2.3.4",
          user_agent: "Firefox"
        })
      )

    assert html =~ "United States"
    assert html =~ Hexpm.Geo.flag_emoji("US")
  end

  test "omits the location when the session has no last use" do
    stub(Hexpm.Geo.Mock, :lookup_country, fn _ -> nil end)

    html = render_card(session(nil))

    assert html =~ "Firefox on macOS"
    refute html =~ "United States"
  end
end

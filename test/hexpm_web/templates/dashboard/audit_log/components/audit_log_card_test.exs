defmodule HexpmWeb.Dashboard.AuditLog.Components.AuditLogCardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias HexpmWeb.Dashboard.AuditLog.Components.AuditLogCard
  alias Hexpm.Accounts.AuditLog

  setup :verify_on_exit!

  defp login_log(attrs \\ %{}) do
    Map.merge(
      %AuditLog{
        action: "session.create",
        remote_ip: "1.2.3.4",
        params: %{"type" => "browser", "name" => "Firefox on macOS"},
        inserted_at: ~U[2026-05-20 12:00:00Z]
      },
      attrs
    )
  end

  test "renders the country name and flag when the IP resolves" do
    stub(Hexpm.Geo.Mock, :lookup_country, fn "1.2.3.4" ->
      %{iso_code: "US", name: "United States"}
    end)

    html = render_component(&AuditLogCard.audit_log_card/1, audit_logs: [login_log()])

    assert html =~ "United States"
    assert html =~ Hexpm.Geo.flag_emoji("US")
  end

  test "omits the location when the IP does not resolve" do
    stub(Hexpm.Geo.Mock, :lookup_country, fn _ -> nil end)

    html =
      render_component(&AuditLogCard.audit_log_card/1,
        audit_logs: [login_log(%{remote_ip: nil})]
      )

    assert html =~ "Logged in from Firefox on macOS"
    refute html =~ "United States"
  end
end

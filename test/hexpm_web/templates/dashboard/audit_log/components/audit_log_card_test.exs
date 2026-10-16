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

  test "describes organization workload identity changes" do
    stub(Hexpm.Geo.Mock, :lookup_country, fn _ -> nil end)

    params = %{
      "repository" => "acme/widget",
      "role" => "write",
      "organization" => %{"name" => "acme"}
    }

    html =
      render_component(&AuditLogCard.audit_log_card/1,
        audit_logs: [
          login_log(%{action: "organization.workload_identity.add", params: params}),
          login_log(%{action: "organization.workload_identity.remove", params: params})
        ]
      )

    assert html =~ "Added the workload identity acme/widget (write) to acme"
    assert html =~ "Removed the workload identity acme/widget (write) from acme"

    any =
      render_component(&AuditLogCard.audit_log_card/1,
        audit_logs: [
          login_log(%{
            action: "organization.workload_identity.add",
            params:
              %{params | "repository" => "", "role" => "read"}
              |> Map.put("repository_owner", "acme")
          })
        ]
      )

    assert any =~ "Added the workload identity for any repository owned by acme (read) to acme"
  end

  test "describes membership visibility changes" do
    stub(Hexpm.Geo.Mock, :lookup_country, fn _ -> nil end)

    params = %{
      "organization" => %{"name" => "acme"},
      "user" => %{"username" => "jane"},
      "public" => true
    }

    html =
      render_component(&AuditLogCard.audit_log_card/1,
        audit_logs: [
          login_log(%{action: "organization.member.visibility", params: params}),
          login_log(%{
            action: "organization.member.visibility",
            params: %{params | "public" => false}
          })
        ]
      )

    assert html =~ "Listed jane on the public profile of acme"
    assert html =~ "Removed jane from the public profile of acme"
  end

  test "describes invitations to accounts and to addresses" do
    stub(Hexpm.Geo.Mock, :lookup_country, fn _ -> nil end)

    organization = %{"name" => "acme"}

    user_invitation = %{
      "organization" => organization,
      "invitation" => %{
        "id" => 1,
        "email" => nil,
        "role" => "read",
        "user" => %{"id" => 2, "username" => "jane"}
      }
    }

    email_invitation = %{
      "organization" => organization,
      "invitation" => %{"id" => 3, "email" => "jane@example.com", "role" => "read"}
    }

    html =
      render_component(&AuditLogCard.audit_log_card/1,
        audit_logs: [
          login_log(%{action: "organization.invitation.create", params: user_invitation}),
          login_log(%{action: "organization.invitation.revoke", params: user_invitation}),
          login_log(%{action: "organization.invitation.decline", params: user_invitation}),
          login_log(%{action: "organization.invitation.restore", params: user_invitation}),
          login_log(%{action: "organization.invitation.block", params: user_invitation}),
          login_log(%{action: "organization.invitation.unblock", params: user_invitation}),
          login_log(%{
            action: "organization.invitation.accept",
            params: put_in(user_invitation, ["invitation", "user"], nil)
          }),
          login_log(%{action: "organization.invitation.create", params: email_invitation}),
          login_log(%{action: "organization.invitation.accept", params: email_invitation})
        ]
      )

    assert html =~ "Invited jane to acme"
    assert html =~ "Revoked the invitation for jane to acme"
    assert html =~ "Declined the invitation to acme"
    assert html =~ "Restored the invitation to acme"
    assert html =~ "Blocked invitations from acme"
    assert html =~ "Unblocked invitations from acme"
    assert html =~ "Accepted the invitation to acme"
    assert html =~ "Invited jane@example.com to acme"
    assert html =~ "Accepted the invitation for jane@example.com to acme"
  end
end

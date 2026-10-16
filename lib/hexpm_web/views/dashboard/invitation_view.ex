defmodule HexpmWeb.Dashboard.InvitationView do
  use HexpmWeb, :view
  import HexpmWeb.Components.Buttons, only: [button: 1]

  defp decline_hold_days do
    div(OrganizationInvitation.decline_hold_seconds(), 24 * 60 * 60)
  end

  defp invitation_details(invitation) do
    inviter =
      if invitation.invited_by_user, do: " by #{invitation.invited_by_user.username}", else: ""

    "Invited#{inviter} as #{invitation.role}, expires #{Calendar.strftime(invitation.expires_at, "%Y-%m-%d")}"
  end
end

defmodule HexpmWeb.Dashboard.InvitationView do
  use HexpmWeb, :view
  import HexpmWeb.Components.Buttons, only: [button: 1]

  defp declined_and_blocked_organizations(invitations, blocks) do
    blocked = Enum.map(blocks, &%{organization: &1.organization, invitation: nil, block: &1})

    declined =
      Enum.map(invitations, &%{organization: &1.organization, invitation: &1, block: nil})

    (blocked ++ declined)
    |> Enum.uniq_by(& &1.organization.id)
    |> Enum.sort_by(& &1.organization.name)
  end

  defp invitation_details(invitation) do
    inviter =
      if invitation.invited_by_user, do: " by #{invitation.invited_by_user.username}", else: ""

    "Invited#{inviter} as #{invitation.role}, expires #{Calendar.strftime(invitation.expires_at, "%Y-%m-%d")}"
  end
end

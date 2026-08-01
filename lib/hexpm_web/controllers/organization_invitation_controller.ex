defmodule HexpmWeb.OrganizationInvitationController do
  use HexpmWeb, :controller

  plug :requires_login

  def show(conn, %{"token" => token}) do
    case OrganizationInvitations.get_pending_by_token(token) do
      nil ->
        expired(conn)

      invitation ->
        render(conn, "show.html",
          title: "Organization invitation",
          container: "container page page-xs",
          invitation: invitation,
          token: token
        )
    end
  end

  def accept(conn, %{"token" => token}) do
    user = conn.assigns.current_user

    case OrganizationInvitations.get_pending_by_token(token) do
      nil ->
        expired(conn)

      invitation ->
        invitation
        |> OrganizationInvitations.accept(user, audit: audit_data(conn))
        |> handle_accept(conn, invitation)
    end
  end

  defp handle_accept({:ok, :already_member}, conn, invitation) do
    conn
    |> put_flash(:info, "You are already a member of #{invitation.organization.name}.")
    |> redirect(to: ~p"/dashboard/orgs/#{invitation.organization}")
  end

  defp handle_accept({:ok, _organization_user}, conn, invitation) do
    conn
    |> put_flash(:info, "You have joined the #{invitation.organization.name} organization.")
    |> redirect(to: ~p"/dashboard/orgs/#{invitation.organization}")
  end

  defp handle_accept({:error, :seats_exhausted}, conn, invitation) do
    conn
    |> put_status(400)
    |> put_flash(
      :error,
      "#{invitation.organization.name} has no seats left. Ask an administrator to add one and try again."
    )
    |> render("show.html",
      title: "Organization invitation",
      container: "container page page-xs",
      invitation: invitation,
      token: nil
    )
  end

  defp handle_accept({:error, :invitation_unavailable}, conn, _invitation) do
    expired(conn)
  end

  defp handle_accept({:error, _reason}, conn, invitation) do
    conn
    |> put_status(400)
    |> put_flash(:error, "Could not join #{invitation.organization.name}.")
    |> render("show.html",
      title: "Organization invitation",
      container: "container page page-xs",
      invitation: invitation,
      token: nil
    )
  end

  # An unknown, spent, revoked, and expired token are all the same answer, so
  # holding one tells you nothing about whether it ever existed.
  defp expired(conn) do
    conn
    |> put_flash(:error, "This invitation is no longer valid. Ask for a new one.")
    |> redirect(to: ~p"/dashboard")
  end
end

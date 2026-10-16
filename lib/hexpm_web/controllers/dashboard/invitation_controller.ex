defmodule HexpmWeb.Dashboard.InvitationController do
  use HexpmWeb, :controller

  plug :requires_login

  def index(conn, _params) do
    render_index(conn)
  end

  def accept(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case pending(user, id) do
      nil ->
        unavailable(conn)

      invitation ->
        invitation
        |> OrganizationInvitations.accept(user, audit: audit_data(conn))
        |> handle_accept(conn, invitation)
    end
  end

  def decline(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with %OrganizationInvitation{} = invitation <- pending(user, id),
         {:ok, _invitation} <-
           OrganizationInvitations.decline(invitation, user, audit: audit_data(conn)) do
      conn
      |> put_flash(
        :info,
        "You declined the invitation to #{invitation.organization.name}."
      )
      |> redirect(to: ~p"/dashboard/invitations")
    else
      _unavailable -> unavailable(conn)
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

  defp handle_accept({:error, :tfa_enrollment_required}, conn, _invitation) do
    conn
    |> put_session(:tfa_return_to, ~p"/dashboard/invitations")
    |> put_flash(
      :error,
      "Enable 2FA before accepting this invitation. Your invitation remains available."
    )
    |> redirect(to: ~p"/dashboard/security")
  end

  defp handle_accept({:error, :seats_exhausted}, conn, invitation) do
    conn
    |> put_status(400)
    |> put_flash(
      :error,
      "#{invitation.organization.name} has no seats left. Ask an administrator to add one and try again."
    )
    |> render_index()
  end

  defp handle_accept({:error, :invitation_unavailable}, conn, _invitation) do
    unavailable(conn)
  end

  defp handle_accept({:error, _reason}, conn, invitation) do
    conn
    |> put_status(400)
    |> put_flash(:error, "Could not join #{invitation.organization.name}.")
    |> render_index()
  end

  defp pending(user, id) do
    case safe_to_integer(id) do
      nil -> nil
      id -> OrganizationInvitations.get_pending_for_user(user, id)
    end
  end

  defp unavailable(conn) do
    conn
    |> put_flash(:error, "This invitation is no longer valid.")
    |> redirect(to: ~p"/dashboard/invitations")
  end

  defp render_index(conn) do
    render(conn, "index.html",
      title: "Dashboard - Invitations",
      container: "container page dashboard",
      invitations: OrganizationInvitations.all_pending_for_user(conn.assigns.current_user)
    )
  end
end

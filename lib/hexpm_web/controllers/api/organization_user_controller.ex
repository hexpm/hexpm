defmodule HexpmWeb.API.OrganizationUserController do
  use HexpmWeb, :controller

  plug :fetch_organization
  plug :assign_tfa_visibility

  plug :authorize,
       [
         domains: [{"api", "read"}],
         fun: {AuthHelpers, :organization_access}
       ]
       when action in [:index, :show]

  plug :authorize,
       [
         domains: [{"api", "write"}],
         fun: {AuthHelpers, :organization_access, [organization_role: "admin"]}
       ]
       when action in [:create, :update, :delete]

  defp assign_tfa_visibility(conn, _opts) do
    user = conn.assigns[:current_user]

    assign(
      conn,
      :tfa_visible?,
      user != nil and Organizations.access?(conn.assigns.organization, user, "admin")
    )
  end

  def index(conn, %{"organization" => name}) do
    organization = Organizations.get(name)
    organization_users = Organizations.all_members(organization, user: :emails)

    conn
    |> api_cache(:private)
    |> render(:index,
      organization_users: organization_users,
      organization: organization,
      tfa_visible?: conn.assigns.tfa_visible?
    )
  end

  def show(conn, %{"organization" => name, "name" => username}) do
    organization = Organizations.get(name)
    user = Users.public_get(username, [:emails])
    role = user && Organizations.get_role(organization, user)

    if role do
      conn
      |> api_cache(:private)
      |> render(:show,
        user: user,
        role: role,
        organization: organization,
        tfa_visible?: conn.assigns.tfa_visible?
      )
    else
      not_found(conn)
    end
  end

  # The member joins once they accept, so this answers 202 with the invitation.
  # An organization key has no person to count the invitation against.
  def create(conn, %{"organization" => name, "name" => username} = params) do
    organization = Organizations.get(name)
    inviter = conn.assigns.current_user

    cond do
      is_nil(inviter) ->
        render_error(conn, 403,
          message: "inviting a member requires a user's credentials, not an organization key"
        )

      user = Users.public_get(username, [:emails]) ->
        params = %{"role" => params["role"]}

        case OrganizationInvitations.invite_user(organization, user, params, inviter,
               audit: audit_data(conn)
             ) do
          {:ok, invitation} ->
            conn
            |> api_cache(:private)
            |> put_status(202)
            |> render(:invitation, user: user, invitation: invitation)

          {:error, :already_member} ->
            validation_failed(conn, "user is already a member of this organization")

          {:error, :blocked} ->
            validation_failed(
              conn,
              "user has blocked invitations from this organization"
            )

          {:error, :invitation_cooldown} ->
            render_error(conn, 429,
              message: "this organization can invite this user once every 24 hours"
            )

          {:error, :too_many_invitations} ->
            render_error(conn, 429,
              message: "too many invitations have been sent to this user or by you recently"
            )

          {:error, :organization_user} ->
            validation_failed(conn, "cannot add an organization as member to an organization")

          {:error, :unverified_primary_email} ->
            validation_failed(
              conn,
              "cannot invite a user who has not verified their primary email"
            )

          {:error, changeset} ->
            validation_failed(conn, changeset)
        end

      true ->
        validation_failed(conn, %{"name" => "unknown user"})
    end
  end

  def update(conn, %{"organization" => name, "name" => username} = params) do
    organization = Organizations.get(name)

    if user = Users.public_get(username, [:emails]) do
      params = %{"role" => params["role"]}

      case Organizations.change_role(organization, user, params, audit: audit_data(conn)) do
        {:ok, organization_user} ->
          conn
          |> api_cache(:private)
          |> render(:show,
            user: user,
            role: organization_user.role,
            organization: organization,
            tfa_visible?: conn.assigns.tfa_visible?
          )

        {:error, :last_admin} ->
          validation_failed(conn, "cannot demote last admin member")

        {:error, changeset} ->
          validation_failed(conn, changeset)
      end
    else
      not_found(conn)
    end
  end

  def delete(conn, %{"organization" => name, "name" => username}) do
    organization = Organizations.get(name)
    user = Users.public_get(username)

    case Organizations.remove_member(organization, user, audit: audit_data(conn)) do
      :ok ->
        conn
        |> api_cache(:private)
        |> send_resp(204, "")

      {:error, :last_admin} ->
        validation_failed(conn, "cannot remove the last eligible administrator")

      {:error, :last_member} ->
        validation_failed(conn, "cannot remove last member")
    end
  end
end

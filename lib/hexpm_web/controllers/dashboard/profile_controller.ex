defmodule HexpmWeb.Dashboard.ProfileController do
  use HexpmWeb, :controller

  plug :requires_login
  plug :requires_verified_primary_email

  def index(conn, _params) do
    user = conn.assigns.current_user
    render_index(conn, User.update_profile(user, %{}))
  end

  def update(conn, params) do
    user = conn.assigns.current_user

    case Users.update_profile(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated successfully.")
        |> redirect(to: ~p"/dashboard/profile")

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_index(changeset)
    end
  end

  def update_membership_visibility(conn, %{
        "organization" => name,
        "organization_user" => %{"public" => _} = params
      }) do
    user = conn.assigns.current_user

    with %Organization{} = organization <- Organizations.get(name),
         {:ok, organization_user} <-
           Organizations.change_visibility(organization, user, params, audit: audit_data(conn)) do
      message =
        if organization_user.public,
          do: "The #{name} organization's profile lists you as a member.",
          else: "The #{name} organization's profile no longer lists you as a member."

      conn
      |> put_flash(:info, message)
      |> redirect(to: ~p"/dashboard/profile")
    else
      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_status(400)
        |> put_flash(:error, "Could not change whether #{name} lists you as a member.")
        |> render_index(User.update_profile(user, %{}))

      _not_member ->
        not_found(conn)
    end
  end

  defp render_index(conn, changeset) do
    render(
      conn,
      "index.html",
      title: "Dashboard - Public profile",
      container: "flex-1 flex flex-col",
      changeset: changeset,
      memberships: Organizations.memberships(conn.assigns.current_user)
    )
  end

  defp requires_verified_primary_email(conn, _opts) do
    if User.verified_primary_email?(conn.assigns.current_user) do
      conn
    else
      conn
      |> put_flash(:error, "Verify your primary email before editing your public profile.")
      |> redirect(to: ~p"/dashboard/email")
      |> halt()
    end
  end
end

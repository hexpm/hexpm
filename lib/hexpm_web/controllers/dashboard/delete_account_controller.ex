defmodule HexpmWeb.Dashboard.DeleteAccountController do
  use HexpmWeb, :controller

  alias HexpmWeb.Plugs.Attack

  plug :requires_login
  plug HexpmWeb.Plugs.Sudo, force: true

  def show(conn, _params) do
    render_show(conn)
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    cond do
      params["username"] != user.username ->
        conn
        |> put_flash(:error, "Entered username does not match your username.")
        |> redirect(to: ~p"/dashboard/delete-account")

      match?({:block, _}, Attack.account_delete_request_throttle(user.id)) ->
        conn
        |> put_flash(:error, "Too many deletion requests. Please try again later.")
        |> redirect(to: ~p"/dashboard/delete-account")

      true ->
        case Users.delete_request(user, audit: audit_data(conn)) do
          :ok ->
            conn
            |> put_flash(
              :info,
              "A confirmation link has been sent to #{User.email(user, :primary)}. " <>
                "It is valid for 24 hours."
            )
            |> redirect(to: ~p"/dashboard/delete-account")

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Your account cannot be deleted right now.")
            |> redirect(to: ~p"/dashboard/delete-account")
        end
    end
  end

  def confirm(conn, params) do
    user = conn.assigns.current_user

    with request when not is_nil(request) <- Users.get_delete_request(user, params["key"]),
         {:ok, warnings} <- Users.delete_eligibility(user) do
      render(conn, "confirm.html",
        title: "Confirm account deletion",
        container: "container page dashboard",
        key: request.key,
        warnings: warnings
      )
    else
      nil ->
        conn
        |> put_flash(:error, "This account deletion link is invalid or has expired.")
        |> redirect(to: ~p"/dashboard/delete-account")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Your account cannot be deleted right now.")
        |> redirect(to: ~p"/dashboard/delete-account")
    end
  end

  def confirm_delete(conn, params) do
    user = conn.assigns.current_user

    case Users.delete_confirm(user, params["key"] || "", audit: audit_data(conn)) do
      :ok ->
        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_flash(:info, "Your account has been permanently deleted.")
        |> redirect(to: ~p"/")

      {:error, :invalid_request} ->
        conn
        |> put_flash(:error, "This account deletion link is invalid or has expired.")
        |> redirect(to: ~p"/dashboard/delete-account")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Your account cannot be deleted right now.")
        |> redirect(to: ~p"/dashboard/delete-account")
    end
  end

  defp render_show(conn) do
    render(conn, "show.html",
      title: "Delete account",
      container: "container page dashboard",
      eligibility: Users.delete_eligibility(conn.assigns.current_user)
    )
  end
end

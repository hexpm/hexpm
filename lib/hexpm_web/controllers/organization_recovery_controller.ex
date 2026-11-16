defmodule HexpmWeb.OrganizationRecoveryController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.OrganizationRecoveries

  plug :requires_login

  # The token rides in the query string, not the path, for the reason given on
  # the invitation routes: the endpoint loggers record `conn.request_path`.
  def show(conn, %{"token" => token}) do
    with_recovery(conn, token, &render_show(&1, &2, token))
  end

  def show(conn, _params), do: unavailable(conn)

  def verify(conn, %{"token" => token} = params) do
    with_recovery(conn, token, fn conn, recovery ->
      user = conn.assigns.current_user

      case OrganizationRecoveries.verify(recovery, user, params["code"]) do
        {:ok, recovery} ->
          conn
          |> put_flash(:info, "Code confirmed.")
          |> render_show(%{recovery | user: user}, token)

        {:error, {:code, reason}} ->
          conn
          |> put_status(400)
          |> put_flash(:error, code_error(reason))
          |> render_show(recovery, token)

        {:error, :billing_unavailable} ->
          conn
          |> put_status(503)
          |> put_flash(:error, "The code could not be checked right now. Try again later.")
          |> render_show(recovery, token)

        {:error, _reason} ->
          unavailable(conn)
      end
    end)
  end

  def verify(conn, _params), do: unavailable(conn)

  # Only the account the recovery names can use the link, and anybody else
  # gets the same answer as for an unknown token.
  defp with_recovery(conn, token, fun) do
    user = conn.assigns.current_user

    case OrganizationRecoveries.get_by_token(token) do
      %{user_id: user_id} = recovery when user_id == user.id -> fun.(conn, recovery)
      _recovery -> unavailable(conn)
    end
  end

  defp render_show(conn, recovery, token) do
    render(conn, "show.html",
      title: "Organization recovery",
      container: "container page page-xs",
      recovery: recovery,
      token: token,
      notice_days: OrganizationRecoveries.notice_days()
    )
  end

  defp code_error("invalid"), do: "That code doesn't match. Check the statement and try again."

  defp code_error("attempts"),
    do: "Too many wrong codes. Contact support@hex.pm to start the recovery again."

  defp code_error("expired"),
    do: "The code has expired. Contact support@hex.pm to start the recovery again."

  defp code_error(_reason),
    do: "The code can't be used. Contact support@hex.pm to start the recovery again."

  defp unavailable(conn) do
    conn
    |> put_flash(:error, "This recovery link is no longer valid. Contact support@hex.pm.")
    |> redirect(to: ~p"/dashboard")
  end
end

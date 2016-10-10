defmodule HexWeb.Mailer do
  def send(template, title, emails, assigns) do
    assigns = [layout: {HexWeb.EmailsView, "layout.html"}] ++ assigns
    body    = Phoenix.View.render(HexWeb.EmailsView, template, assigns)

    HexWeb.Email.send(emails, title, body)
  end

  def send_owner_added_email(package, owners, owner) do
    send(
      "owner_add.html",
      "Hex.pm - Owner added",
      Enum.map(owners, & &1.email),
      username: owner.username,
      email: owner.email,
      package: package.name
    )
  end

  def send_owner_removed_email(package, owners, owner) do
    send(
      "owner_remove.html",
      "Hex.pm - Owner removed",
      Enum.map(owners, & &1.email),
      username: owner.username,
      email: owner.email,
      package: package.name
    )
  end

  def send_user_confirmed_email(user) do
    send(
      "confirmed.html",
      "Hex.pm - Email confirmed",
      [user.email],
      []
    )
  end

  def send_confirmation_request_email(user) do
    send(
      "confirmation_request.html",
      "Hex.pm - Email confirmation",
      [user.email],
      username: user.username,
      key: user.confirmation_key)
  end

  def send_password_reset_request_email(user) do
    send(
      "password_reset_request.html",
      "Hex.pm - Password reset request",
      [user.email],
      username: user.username,
      key: user.reset_key)
  end

  def send_password_reset_email(user) do
    send(
      "password_reset.html",
      "Hex.pm - Password reset",
      [user.email],
      [])
  end

  def send_typosquat_candidates_email([], _), do: :ok
  def send_typosquat_candidates_email(candidates, threshold) do
    send(
      "typosquat_candidates.html",
      "Hex.pm - Typosquat candidates",
      [Application.get_env(:hex_web, :support_email)],
      candidates: candidates,
      threshold: threshold)
  end
end

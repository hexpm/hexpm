defmodule HexWeb.Mailer do
  def send(template, title, emails, assigns) do
    assigns = [layout: {HexWeb.EmailsView, "layout.html"}] ++ assigns
    body    = Phoenix.View.render(HexWeb.EmailsView, template, assigns)

    HexWeb.Mail.send(emails, title, body)
  end

  def send_owner_added_email(package, owners, owner) do
    send(
      "owner_add.html",
      "Hex.pm - Owner added",
      email(owners),
      username: owner.username,
      email: email(owner),
      package: package.name
    )
  end

  def send_owner_removed_email(package, owners, owner) do
    send(
      "owner_remove.html",
      "Hex.pm - Owner removed",
      email(owners),
      username: owner.username,
      email: email(owner),
      package: package.name
    )
  end

  def send_verification_email(user, email) do
    send(
      "verification.html",
      "Hex.pm - Email verification",
      [email.email],
      username: user.username,
      email: email.email,
      key: email.verification_key)
  end

  def send_password_reset_request_email(user) do
    send(
      "password_reset_request.html",
      "Hex.pm - Password reset request",
      email(user),
      username: user.username,
      key: user.reset_key)
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

  defp email(%HexWeb.User{} = user),
    do: [HexWeb.User.email(user, :primary)]
  defp email(users) when is_list(users),
    do: Enum.flat_map(users, &email/1)
end

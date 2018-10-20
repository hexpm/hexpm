defmodule Hexpm.Emails do
  import Bamboo.Email
  use Bamboo.Phoenix, view: HexpmWeb.EmailView

  def owner_added(package, owners, owner) do
    email()
    |> email_to(owners)
    |> subject("Hex.pm - Owner added to package #{package.name}")
    |> assign(:username, owner.username)
    |> assign(:package, package.name)
    |> render("owner_add.html")
  end

  def owner_removed(package, owners, owner) do
    email()
    |> email_to(owners)
    |> subject("Hex.pm - Owner removed from package #{package.name}")
    |> assign(:username, owner.username)
    |> assign(:package, package.name)
    |> render("owner_remove.html")
  end

  def verification(user, email) do
    email()
    |> email_to(%{email | user: user})
    |> subject("Hex.pm - Email verification")
    |> assign(:username, user.username)
    |> assign(:email, email.email)
    |> assign(:key, email.verification_key)
    |> render("verification.html")
  end

  def password_reset_request(user, reset) do
    email()
    |> email_to(user)
    |> subject("Hex.pm - Password reset request")
    |> assign(:username, user.username)
    |> assign(:key, reset.key)
    |> render("password_reset_request.html")
  end

  def password_changed(user) do
    email()
    |> email_to(user)
    |> subject("Hex.pm - Your password has changed")
    |> assign(:username, user.username)
    |> render("password_changed.html")
  end

  def typosquat_candidates(candidates, threshold) do
    email()
    |> email_to(Application.get_env(:hexpm, :support_email))
    |> subject("[TYPOSQUAT CANDIDATES]")
    |> assign(:candidates, candidates)
    |> assign(:threshold, threshold)
    |> render("typosquat_candidates.html")
  end

  def organization_invite(organization, user) do
    email()
    |> email_to(user)
    |> subject("Hex.pm - You have been added to the #{organization.name} organization")
    |> assign(:organization, organization.name)
    |> assign(:username, user.username)
    |> render("organization_invite.html")
  end

  defp email_to(email, to) do
    to = to |> List.wrap() |> Enum.sort()
    to(email, to)
  end

  defp email() do
    new_email()
    |> from(source())
    |> put_html_layout({HexpmWeb.EmailView, "layout.html"})
  end

  defp source() do
    host = Application.get_env(:hexpm, :email_host) || "hex.pm"
    {"Hex.pm", "noreply@#{host}"}
  end
end

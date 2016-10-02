defmodule HexWeb.Mail do
  import Bamboo.Email
  use Bamboo.Phoenix, view: HexWeb.EmailView

  def owner_added(package, owners, owner) do
    owner_email = hd(owner.emails).email

    new_email
    |> to(owners)
    |> from(source)
    |> subject("Hex.pm - Owner added")
    |> assign(:username, owner.username)
    |> assign(:email, owner_email)
    |> assign(:package, package.name)
    |> render("owner_add.html")
  end

  def owner_removed(package, owners, owner) do
    owner_email = hd(owner.emails).email

    new_email
    |> to(owners)
    |> from(source)
    |> subject("Hex.pm - Owner removed")
    |> assign(:username, owner.username)
    |> assign(:email, owner_email)
    |> assign(:package, package.name)
    |> render("owner_remove.html")
  end

  def verification(user, email) do
    new_email
    |> to(user)
    |> from(source)
    |> subject("Hex.pm - Email verification")
    |> assign(:username, user.username)
    |> assign(:email, email.email)
    |> assign(:key, email.verification_key)
    |> render("verification.html")
  end

  def user_confirmed(user) do
    new_email
    |> to(user)
    |> from(source)
    |> subject("Hex.pm - Account confirmed")
    |> render("confirmed.html")
  end

  def password_reset_request(user) do
    new_email
    |> to(user)
    |> from(source)
    |> subject("Hex.pm - Password reset request")
    |> assign(:username, user.username)
    |> assign(:key, user.reset_key)
    |> render("password_reset_request.html")
  end

  def typosquat_candidates([], _), do: :ok
  def typosquat_candidate(candidates, threshold) do
    new_email
    |> to(Application.get_env(:hex_web, :support_email))
    |> from(source)
    |> subject("Hex.pm - Typosquat candidates")
    |> assign(:candidates, candidates)
    |> assign(:threshold, threshold)
    |> render("typosquat_candidates.html")
  end

  defp source do
    host = Application.get_env(:hex_web, :email_host) || "hex.pm"
    "Hex.pm <noreply@#{host}>"
  end
end

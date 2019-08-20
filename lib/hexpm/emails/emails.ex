defmodule Hexpm.Emails do
  use Bamboo.Phoenix, view: HexpmWeb.EmailView
  import Bamboo.Email
  alias Hexpm.Accounts.{Email, User}

  def owner_added(package, owners, owner) do
    email()
    |> email_to(owners)
    |> subject("Hex.pm - Owner added to package #{package.name}")
    |> assign(:username, owner.username)
    |> assign(:package, package.name)
    |> render(:owner_add)
  end

  def owner_removed(package, owners, owner) do
    email()
    |> email_to(owners)
    |> subject("Hex.pm - Owner removed from package #{package.name}")
    |> assign(:username, owner.username)
    |> assign(:package, package.name)
    |> render(:owner_remove)
  end

  def verification(user, email) do
    email()
    |> email_to(%{email | user: user})
    |> subject("Hex.pm - Email verification")
    |> assign(:username, user.username)
    |> assign(:email, email.email)
    |> assign(:key, email.verification_key)
    |> render(:verification)
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

  def package_published(user, name, version) do
    email()
    |> email_to(user)
    |> subject("Hex.pm - Package #{name} v#{version} published")
    |> assign(:version, version)
    |> assign(:package, name)
    |> render(:package_published)
  end

  defp email_to(email, to) do
    to =
      to
      |> List.wrap()
      |> Enum.flat_map(&expand_organization/1)
      |> Enum.sort()

    to(email, to)
  end

  defp expand_organization(%Email{} = email), do: [email]
  defp expand_organization(%User{organization: nil} = user), do: [user]
  defp expand_organization(%User{organization: %Ecto.Association.NotLoaded{}} = user), do: [user]

  defp expand_organization(%User{organization: organization}) do
    organization.organization_users
    |> Enum.filter(&(&1.role == "admin"))
    |> Enum.map(&User.email(&1.user, :primary))
  end

  defp email() do
    new_email()
    |> from(source())
    |> put_layout({HexpmWeb.EmailView, :layout})
  end

  defp source() do
    host = Application.get_env(:hexpm, :email_host) || "hex.pm"
    {"Hex.pm", "noreply@#{host}"}
  end
end

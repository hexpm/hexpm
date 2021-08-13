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
    |> render(:password_reset_request)
  end

  def password_changed(user) do
    email()
    |> email_to(user)
    |> subject("Hex.pm - Your password has changed")
    |> assign(:username, user.username)
    |> render(:password_changed)
  end

  def typosquat_candidates(candidates, threshold) do
    email()
    |> email_to(Application.get_env(:hexpm, :support_email))
    |> subject("[TYPOSQUAT CANDIDATES]")
    |> assign(:candidates, candidates)
    |> assign(:threshold, threshold)
    |> render(:typosquat_candidates)
  end

  def organization_invite(organization, user) do
    email()
    |> email_to(user)
    |> subject("Hex.pm - You have been added to the #{organization.name} organization")
    |> assign(:organization, organization.name)
    |> assign(:username, user.username)
    |> render(:organization_invite)
  end

  def package_published(owners, publisher, name, version) do
    email()
    |> email_to(owners)
    |> subject("Hex.pm - Package #{name} v#{version} published")
    |> assign(:publisher, publisher)
    |> assign(:version, version)
    |> assign(:package, name)
    |> render(:package_published)
  end

  def report_submitted(receiver, author_name, package_name, report_id, inserted_at) do
    email()
    |> email_to(receiver)
    |> subject("Hex.pm - Package report on #{package_name} published ")
    |> assign(:package_name, package_name)
    |> assign(:author_name, author_name)
    |> assign(:report_id, report_id)
    |> assign(:inserted_at, inserted_at)
    |> render(:report_submitted)
  end

  def report_commented(receiver, author_name, report_id, inserted_at) do
    email()
    |> email_to(receiver)
    |> subject("Hex.pm - New comment on package report ##{report_id}")
    |> assign(:author_name, author_name)
    |> assign(:report_id, report_id)
    |> assign(:inserted_at, inserted_at)
    |> render(:report_commented)
  end

  def report_state_changed(receiver, report_id, new_state, updated_at) do
    email()
    |> email_to(receiver)
    |> subject("Hex.pm - Package report ##{report_id} has been reviewed by a moderator")
    |> assign(:report_id, report_id)
    |> assign(:new_state, new_state)
    |> assign(:updated_at, updated_at)
    |> render(:report_state_changed)
  end

  defp email_to(email, to) do
    to =
      to
      |> List.wrap()
      |> Enum.flat_map(&expand_organization/1)
      |> Enum.sort()

    to(email, to)
  end

  defp expand_organization(email) when is_binary(email), do: [email]
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

defmodule Hexpm.Emails do
  use Phoenix.Swoosh, view: HexpmWeb.EmailView
  alias Hexpm.Accounts.{Email, Organization, User}

  def owner_added(package, owners, owner) do
    base_email()
    |> email_to(owners)
    |> subject("Hex.pm - Owner added to package #{package.name}")
    |> assign(:username, owner.username)
    |> assign(:package, package.name)
    |> render_body(:owner_add)
  end

  def owner_removed(package, owners, owner) do
    base_email()
    |> email_to(owners)
    |> subject("Hex.pm - Owner removed from package #{package.name}")
    |> assign(:username, owner.username)
    |> assign(:package, package.name)
    |> render_body(:owner_remove)
  end

  def verification(user, email) do
    base_email()
    |> email_to(%{email | user: user})
    |> subject("Hex.pm - Email verification")
    |> assign(:username, user.username)
    |> assign(:email_address, email.email)
    |> assign(:key, email.verification_key)
    |> render_body(:verification)
  end

  def password_reset_request(user, reset) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - Password reset request")
    |> assign(:username, user.username)
    |> assign(:key, reset.key)
    |> render_body(:password_reset_request)
  end

  def security_password_reset(user, reset) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - Your password has been reset for security reasons")
    |> assign(:username, user.username)
    |> assign(:key, reset.key)
    |> render_body(:security_password_reset)
  end

  def password_changed(user) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - Your password has changed")
    |> assign(:username, user.username)
    |> render_body(:password_changed)
  end

  def tfa_enabled(user) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - TFA has been enabled on your account")
    |> assign(:username, user.username)
    |> render_body(:tfa_enabled)
  end

  def tfa_disabled(user) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - TFA has been disabled on your account")
    |> assign(:username, user.username)
    |> render_body(:tfa_disabled)
  end

  def tfa_rotate_recovery_codes(user) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - Your TFA recovery codes have been rotated")
    |> assign(:username, user.username)
    |> render_body(:tfa_recovery_rotated)
  end

  def email_added(user, new_email) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - A new email address was added to your account")
    |> assign(:username, user.username)
    |> assign(:new_email, new_email.email)
    |> render_body(:email_added)
  end

  def primary_email_changed(user, old_addr, new_addr) do
    base_email()
    |> email_to(old_addr)
    |> subject("Hex.pm - Your primary email address has changed")
    |> assign(:username, user.username)
    |> assign(:old_addr, old_addr)
    |> assign(:new_addr, new_addr)
    |> render_body(:primary_email_changed)
  end

  def api_key_created(user_or_org, key) do
    base_email()
    |> email_to(user_or_org)
    |> subject("Hex.pm - A new API key was created on your account")
    |> assign(:username, display_name(user_or_org))
    |> assign(:key_name, key.name)
    |> render_body(:api_key_created)
  end

  def api_key_revoked(user_or_org, key) do
    base_email()
    |> email_to(user_or_org)
    |> subject("Hex.pm - An API key was revoked on your account")
    |> assign(:username, display_name(user_or_org))
    |> assign(:key_name, key.name)
    |> render_body(:api_key_revoked)
  end

  def api_keys_all_revoked(user_or_org) do
    base_email()
    |> email_to(user_or_org)
    |> subject("Hex.pm - All API keys have been revoked on your account")
    |> assign(:username, display_name(user_or_org))
    |> render_body(:api_keys_all_revoked)
  end

  def typosquat_candidates(candidates, threshold) do
    base_email()
    |> email_to(Application.get_env(:hexpm, :support_email))
    |> subject("[TYPOSQUAT CANDIDATES]")
    |> assign(:candidates, candidates)
    |> assign(:threshold, threshold)
    |> render_body(:typosquat_candidates)
  end

  def organization_invite(organization, user) do
    base_email()
    |> email_to(user)
    |> subject("Hex.pm - You have been added to the #{organization.name} organization")
    |> assign(:organization, organization.name)
    |> assign(:username, user.username)
    |> render_body(:organization_invite)
  end

  def package_published(owners, publisher, name, version) do
    base_email()
    |> email_to(owners)
    |> subject("Hex.pm - Package #{name} v#{version} published")
    |> assign(:publisher, publisher)
    |> assign(:version, version)
    |> assign(:package, name)
    |> render_body(:package_published)
  end

  def report_submitted(receiver, author_name, package_name, report_id, inserted_at) do
    base_email()
    |> email_to(receiver)
    |> subject("Hex.pm - Package report on #{package_name} published ")
    |> assign(:package_name, package_name)
    |> assign(:author_name, author_name)
    |> assign(:report_id, report_id)
    |> assign(:inserted_at, inserted_at)
    |> render_body(:report_submitted)
  end

  def report_commented(receiver, author_name, report_id, inserted_at) do
    base_email()
    |> email_to(receiver)
    |> subject("Hex.pm - New comment on package report ##{report_id}")
    |> assign(:author_name, author_name)
    |> assign(:report_id, report_id)
    |> assign(:inserted_at, inserted_at)
    |> render_body(:report_commented)
  end

  def report_state_changed(receiver, report_id, new_state, updated_at) do
    base_email()
    |> email_to(receiver)
    |> subject("Hex.pm - Package report ##{report_id} has been reviewed by a moderator")
    |> assign(:report_id, report_id)
    |> assign(:new_state, new_state)
    |> assign(:updated_at, updated_at)
    |> render_body(:report_state_changed)
  end

  defp email_to(email, to) do
    recipients =
      to
      |> List.wrap()
      |> Enum.flat_map(&expand_organization/1)
      |> Enum.reject(&is_nil(recipient_email(&1)))
      |> Enum.sort_by(&recipient_email/1)
      |> Enum.uniq_by(&recipient_email/1)
      |> Enum.map(&to_recipient/1)

    Swoosh.Email.to(email, recipients)
  end

  defp to_recipient(email) when is_binary(email), do: email
  defp to_recipient(%Email{} = email), do: {email.user.username, email.email}
  defp to_recipient(%User{} = user), do: {user.username, User.email(user, :primary)}

  defp recipient_email(nil), do: nil
  defp recipient_email(email) when is_binary(email), do: email
  defp recipient_email(%Email{email: email}), do: email
  defp recipient_email(%User{} = user), do: User.email(user, :primary)

  defp expand_organization(email) when is_binary(email), do: [email]
  defp expand_organization(%Email{} = email), do: [email]
  defp expand_organization(%User{organization: nil} = user), do: [user]
  defp expand_organization(%User{organization: %Ecto.Association.NotLoaded{}} = user), do: [user]

  defp expand_organization(
         %User{organization: %{organization_users: %Ecto.Association.NotLoaded{}}} = user
       ) do
    [user]
  end

  defp expand_organization(%User{organization: organization}) do
    organization.organization_users
    |> Enum.filter(&(&1.role == "admin"))
    |> Enum.map(&User.email(&1.user, :primary))
  end

  defp expand_organization(%Organization{organization_users: org_users}) do
    admins =
      org_users
      |> Enum.filter(&(&1.role == "admin"))
      |> Enum.map(&User.email(&1.user, :primary))

    if admins == [] do
      Enum.map(org_users, &User.email(&1.user, :primary))
    else
      admins
    end
  end

  defp display_name(%User{username: username}), do: username
  defp display_name(%Organization{name: name}), do: name

  defp base_email() do
    new()
    |> from(source())
    |> put_layout({HexpmWeb.EmailView, :layout})
    |> put_provider_option(:click_tracking, %{enable: false})
  end

  defp source() do
    host = Application.get_env(:hexpm, :email_host) || "hex.pm"
    {"Hex.pm", "noreply@#{host}"}
  end
end

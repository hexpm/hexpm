defmodule Hexpm.Accounts.User do
  use Hexpm.Schema

  @derive {HexpmWeb.Stale, assocs: [:emails, :owned_packages, :organizations, :keys]}
  @derive {Phoenix.Param, key: :username}

  alias Hexpm.Accounts.{RecoveryCode, TFA}

  schema "users" do
    field :username, :string
    field :full_name, :string
    field :password, :string
    field :service, :boolean, default: false
    field :deactivated_at, :utc_datetime_usec
    field :tfa_enabled, :boolean, default: false
    field :verification_code, :string, virtual: true
    timestamps()

    embeds_one :handles, UserHandles, on_replace: :delete
    embeds_one :tfa, TFA, on_replace: :delete

    belongs_to :organization, Organization
    has_many :emails, Email
    has_many :package_owners, PackageOwner
    has_many :owned_packages, through: [:package_owners, :package]
    has_many :organization_users, OrganizationUser
    has_many :organizations, through: [:organization_users, :organization]
    has_many :keys, Key
    has_many :audit_logs, AuditLog
    has_many :password_resets, PasswordReset
  end

  @username_regex ~r"^[a-z0-9_\-\.]+$"

  @reserved_names ~w(me hex hexpm elixir erlang otp)

  def build(params, confirmed? \\ not Application.get_env(:hexpm, :user_confirm)) do
    cast(%User{}, params, ~w(username full_name password)a)
    |> validate_required(~w(username password)a)
    |> cast_assoc(:emails, required: true, with: &Email.changeset(&1, :first, &2, confirmed?))
    |> cast_embed(:tfa)
    |> update_change(:username, &String.downcase/1)
    |> validate_length(:username, min: 3)
    |> validate_format(:username, @username_regex)
    |> validate_exclusion(:username, @reserved_names)
    |> unique_constraint(:username, name: "users_username_idx")
    |> validate_length(:password, min: 7)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &Auth.gen_password/1)
  end

  def build_organization(organization) do
    username = organization_name(organization)

    change(%User{username: username, organization_id: organization.id}, %{})
    |> update_change(:username, &String.downcase/1)
    |> validate_length(:username, min: 3)
    |> validate_format(:username, @username_regex)
    |> validate_exclusion(:username, @reserved_names)
    |> unique_constraint(:username, name: "users_username_idx")
  end

  def to_organization(user, organization) do
    change(user, %{password: nil, organization_id: organization.id})
  end

  def update_profile(user, params) do
    cast(user, params, ~w(full_name)a)
    |> cast_embed(:handles)
  end

  def update_password_no_check(user, params) do
    cast(user, params, ~w(password)a)
    |> validate_required(~w(password)a)
    |> validate_length(:password, min: 7)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &Auth.gen_password/1)
  end

  def update_password(user, params) do
    password = user.password
    user = %{user | password: nil}

    cast(user, params, ~w(password)a)
    |> validate_required(~w(password)a)
    |> validate_length(:password, min: 7)
    |> validate_password(:password, password)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &Auth.gen_password/1)
  end

  def update_security(user, params) do
    user
    |> cast(params, ~w(tfa_enabled)a)
    |> maybe_update_tfa()
  end

  def update_two_factor_auth(user, params) do
    cast(user, params, ~w(verification_code)a)
  end

  def can_reset_password?(user, key) do
    primary_email = email(user, :primary)

    Enum.any?(user.password_resets, fn reset ->
      PasswordReset.can_reset?(reset, primary_email, key)
    end)
  end

  def email(user, :primary), do: user.emails |> Enum.find(& &1.primary) |> email()
  def email(user, :public), do: user.emails |> Enum.find(& &1.public) |> email()
  def email(user, :gravatar), do: user.emails |> Enum.find(& &1.gravatar) |> email()

  defp email(nil), do: nil
  defp email(email), do: email.email

  def get(username_or_email, preload \\ []) do
    from(
      u in Hexpm.Accounts.User,
      where:
        u.username == ^username_or_email or
          ^username_or_email in fragment(
            "SELECT emails.email FROM emails WHERE emails.user_id = ? and emails.verified",
            u.id
          ),
      preload: ^preload
    )
  end

  def public_get(username_or_email, preload \\ []) do
    from(
      u in Hexpm.Accounts.User,
      where:
        u.username == ^username_or_email or
          ^username_or_email in fragment(
            "SELECT emails.email FROM emails WHERE emails.user_id = ? and emails.verified and emails.public",
            u.id
          ),
      preload: ^preload
    )
  end

  def verify_permissions(%User{}, "api", _resource) do
    {:ok, nil}
  end

  def verify_permissions(%User{}, "repositories", nil) do
    {:ok, nil}
  end

  def verify_permissions(%User{}, "repository", nil) do
    :error
  end

  def verify_permissions(%User{} = user, domain, name) when domain in ["repository", "docs"] do
    organization = Organizations.get(name)

    if organization && Organizations.access?(organization, user, "read") do
      {:ok, organization}
    else
      :error
    end
  end

  def verify_permissions(%User{}, _domain, _resource) do
    :error
  end

  def organization?(user), do: user.organization_id != nil

  # Workaround for compatability with older Hex client tests, fixed in Hex v0.20.1
  if Mix.env() == :hex do
    defp organization_name(organization), do: organization.name <> "-orguser"
  else
    defp organization_name(organization), do: organization.name
  end

  defp maybe_update_auth_secret(%{changes: %{tfa_enabled: true}} = changeset) do
    secret = Hexpm.Accounts.TwoFactorAuth.generate_secret()
    # are the codes being deleted here?
    put_change(changeset, :tfa, %{secret: secret})
  end

  def recovery_code_used(user, code) do
    updated_codes = Enum.map(user.tfa.recovery_codes, &set_recovery_code_used(&1, code))
    change(user, %{tfa: %{recovery_codes: updated_codes}})
  end

  def rotate_recovery_codes(user) do
    codes = Hexpm.Accounts.Recovery.gen_code_set()
    change(user, %{tfa: %{secret: user.tfa.secret, recovery_codes: codes}})
  end

  defp maybe_update_tfa(%{changes: %{tfa_enabled: true}} = changeset) do
    secret = Hexpm.Accounts.TwoFactorAuth.generate_secret()
    codes = Hexpm.Accounts.Recovery.gen_code_set()
    put_change(changeset, :tfa, %{secret: secret, recovery_codes: codes})
  end

  defp maybe_update_tfa(%{changes: %{tfa_enabled: false}} = changeset),
    do: put_change(changeset, :tfa, nil)

  defp maybe_update_tfa(changeset), do: changeset

  defp set_recovery_code_used(%RecoveryCode{code: code_str}, %RecoveryCode{code: code_str} = code) do
    %{code | used_at: DateTime.utc_now()}
  end

  defp set_recovery_code_used(code, _other), do: code
end

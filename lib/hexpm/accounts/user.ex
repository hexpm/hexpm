defmodule Hexpm.Accounts.User do
  use Hexpm.Web, :schema

  @derive {Hexpm.Web.Stale, assocs: [:emails, :owned_packages, :repositories, :keys]}
  @derive {Phoenix.Param, key: :username}

  schema "users" do
    field :username, :string
    field :full_name, :string
    field :password, :string
    timestamps()

    field :reset_key, :string
    field :reset_expiry, :naive_datetime

    embeds_one :handles, UserHandles, on_replace: :delete

    has_many :emails, Email
    has_many :package_owners, PackageOwner, foreign_key: :owner_id
    has_many :owned_packages, through: [:package_owners, :package]
    has_many :repository_users, RepositoryUser
    has_many :repositories, through: [:repository_users, :repository]
    has_many :keys, Key
    has_many :audit_logs, AuditLog, foreign_key: :actor_id
  end

  @username_regex ~r"^[a-z0-9_\-\.\(\)]+$"

  @reserved_names ~w(me hex hexpm elixir erlang otp)

  defp changeset(user, :create, params, confirmed?) do
    cast(user, params, ~w(username full_name password))
    |> validate_required(~w(username password)a)
    |> cast_assoc(:emails, required: true, with: &Email.changeset(&1, :first, &2, confirmed?))
    |> update_change(:username, &String.downcase/1)
    |> validate_length(:username, min: 3)
    |> validate_format(:username, @username_regex)
    |> validate_exclusion(:username, @reserved_names)
    |> unique_constraint(:username, name: "users_username_idx")
    |> validate_length(:password, min: 7)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &Auth.gen_password/1)
  end

  def build(params, confirmed? \\ not Application.get_env(:hexpm, :user_confirm)) do
    changeset(%Hexpm.Accounts.User{}, :create, params, confirmed?)
  end

  def update_profile(user, params) do
    cast(user, params, ~w(full_name))
    |> cast_embed(:handles)
  end

  def update_password_no_check(user, params) do
    cast(user, params, ~w(password))
    |> validate_required(~w(password)a)
    |> validate_length(:password, min: 7)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &Auth.gen_password/1)
  end

  def update_password(user, params) do
    password = user.password
    user = %{user | password: nil}

    cast(user, params, ~w(password))
    |> validate_required(~w(password)a)
    |> validate_length(:password, min: 7)
    |> validate_password(:password, password)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &Auth.gen_password/1)
  end

  def init_password_reset(user) do
    key = Auth.gen_key()
    change(user, %{reset_key: key, reset_expiry: NaiveDateTime.utc_now()})
  end

  def disable_password_reset(user) do
    change(user, %{reset_key: nil, reset_expiry: nil})
  end

  def password_reset?(nil, _key), do: false
  def password_reset?(user, key) do
    !!(user.reset_key &&
       Comeonin.Tools.secure_check(user.reset_key, key) &&
       Hexpm.Utils.within_last_day(user.reset_expiry))
  end

  def password_reset(user, params, revoke_all_keys \\ true) do
    multi =
      Multi.new()
      |> Multi.update(:password, update_password_no_check(user, params))
      |> Multi.update(:reset, disable_password_reset(user))
      |> Multi.delete_all(:reset_sessions, Session.by_user(user))

    if revoke_all_keys,
      do: Multi.update_all(multi, :keys, Key.revoke_all(user), []),
    else: multi
  end

  def email(user, :primary), do: user.emails |> Enum.find(& &1.primary) |> email()
  def email(user, :public), do: user.emails |> Enum.find(& &1.public) |> email()

  defp email(nil), do: nil
  defp email(email), do: email.email

  def get(username_or_email, preload \\ []) do
    # Somewhat crazy hack to get this done in one query
    # Makes assumptions about how Ecto choses variable names
    from(u in Hexpm.Accounts.User,
      where: u.username == ^username_or_email or
             ^username_or_email in fragment("SELECT emails.email FROM emails WHERE emails.user_id = u0.id and emails.verified"),
      preload: ^preload)
  end

  def verify_permissions?(_user, "api", _resource) do
    true
  end
  def verify_permissions?(user, "repository", name) do
    if repository = Repositories.get(name) do
      Repositories.access?(repository, user, "read")
    else
      false
    end
  end
  def verify_permissions?(_user, _domain, _resource) do
    false
  end
end

defmodule HexWeb.User do
  use HexWeb.Web, :model

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
    has_many :keys, Key
    has_many :audit_logs, AuditLog, foreign_key: :actor_id
  end

  @username_regex ~r"^[a-z0-9_\-\.!~\*'\(\)]+$"

  defp changeset(user, :create, params, confirmed?) do
    cast(user, params, ~w(username full_name password))
    |> validate_required(~w(username password)a)
    |> cast_assoc(:emails, required: true, with: &Email.changeset(&1, :first, &2, confirmed?))
    |> update_change(:username, &String.downcase/1)
    |> validate_length(:username, min: 3)
    |> validate_format(:username, @username_regex)
    |> unique_constraint(:username, name: "users_username_idx")
    |> validate_length(:password, min: 7)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &HexWeb.Auth.gen_password/1)
  end

  def build(params, confirmed? \\ not Application.get_env(:hex_web, :user_confirm)) do
    changeset(%HexWeb.User{}, :create, params, confirmed?)
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
    |> update_change(:password, &HexWeb.Auth.gen_password/1)
  end

  def update_password(user, params) do
    password = user.password
    user = %{user | password: nil}

    cast(user, params, ~w(password))
    |> validate_required(~w(password)a)
    |> validate_length(:password, min: 7)
    |> validate_password(:password, password)
    |> validate_confirmation(:password, message: "does not match password")
    |> update_change(:password, &HexWeb.Auth.gen_password/1)
  end

  def init_password_reset(user) do
    key = HexWeb.Auth.gen_key()
    change(user, %{reset_key: key, reset_expiry: HexWeb.Utils.utc_now})
  end

  def password_reset?(nil, _key), do: false
  def password_reset?(user, key) do
    !!(user.reset_key &&
       Comeonin.Tools.secure_check(user.reset_key, key) &&
       HexWeb.Utils.within_last_day(user.reset_expiry))
  end

  def password_reset(user, params, revoke_all_keys \\ true) do
    multi =
      Ecto.Multi.new
      |> Ecto.Multi.update(:password, update_password_no_check(user, params))
      |> Ecto.Multi.update(:reset, change(user, %{reset_key: nil, reset_expiry: nil}))

    if revoke_all_keys,
      do: Ecto.Multi.update_all(multi, :keys, Key.revoke_all(user), []),
    else: multi
  end

  def email(user, :primary), do: user.emails |> Enum.find(& &1.primary) |> email
  def email(user, :public), do: user.emails |> Enum.find(& &1.public) |> email

  defp email(nil), do: nil
  defp email(email), do: email.email
end

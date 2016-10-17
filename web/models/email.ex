defmodule HexWeb.Email do
  use HexWeb.Web, :model

  schema "emails" do
    field :email, :string
    field :verified, :boolean
    field :primary, :boolean
    field :public, :boolean
    field :verification_key, :string

    belongs_to :user, User
  end

  @email_regex ~r"^.+@.+\..+$"

  def changeset(email, :first, params, verified?) do
    changeset(email, :create, params, verified?)
    |> put_change(:primary, true)
    |> put_change(:public, true)
  end

  def changeset(email, :create, params, verified?) do
    cast(email, params, ~w(email))
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, @email_regex)
    |> validate_confirmation(:email, message: "does not match email")
    |> unique_constraint(:email, name: "emails_email_key")
    |> put_change(:verified, verified?)
    |> put_change(:verification_key, HexWeb.Auth.gen_key())
  end

  def verify?(nil, _key),
    do: false
  def verify?(email, key),
    do: Comeonin.Tools.secure_check(email.verification_key, key)

  def verify(email) do
    change(email, %{verified: true})
  end
end

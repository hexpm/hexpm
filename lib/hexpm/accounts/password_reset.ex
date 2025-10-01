defmodule Hexpm.Accounts.PasswordReset do
  use Hexpm.Schema

  schema "password_resets" do
    field :key, :string
    field :primary_email, :string
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(reset, user) do
    change(reset, %{
      key: Auth.gen_key(),
      primary_email: User.email(user, :primary)
    })
  end

  def can_reset?(%__MODULE__{} = reset, primary_email, key) do
    reset.key == key && reset.primary_email == primary_email
  end
end

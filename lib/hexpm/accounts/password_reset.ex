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

  def can_reset?(reset, primary_email, key) do
    valid_email? = primary_email == reset.primary_email
    valid_key? = !!(reset.key && Hexpm.Utils.secure_check(reset.key, key))
    within_time? = Hexpm.Utils.within_last_day?(reset.inserted_at)

    valid_email? and valid_key? and within_time?
  end
end

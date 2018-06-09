defmodule Hexpm.Accounts.PasswordReset do
  use Hexpm.Web, :schema

  schema "password_resets" do
    field :key, :string
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(reset) do
    change(reset, %{key: Auth.gen_key()})
  end

  def can_reset?(reset, key) do
    !!(reset.key && Hexpm.Utils.secure_check(reset.key, key) &&
         Hexpm.Utils.within_last_day(reset.inserted_at))
  end
end

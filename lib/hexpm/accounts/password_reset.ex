defmodule Hexpm.Accounts.PasswordReset do
  use Hexpm.Schema

  schema "password_resets" do
    field :key_hash, :binary, redact: true
    field :key, :string, virtual: true, redact: true
    field :primary_email, :string
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(reset, user) do
    key = Auth.gen_key()

    change(reset, %{
      key: key,
      key_hash: hash(key),
      primary_email: User.email(user, :primary)
    })
  end

  def can_reset?(reset, primary_email, key) do
    valid_email? = primary_email == reset.primary_email
    valid_key? = is_binary(key) and Plug.Crypto.secure_compare(reset.key_hash, hash(key))
    within_time? = Hexpm.Utils.within_last_day?(reset.inserted_at)

    valid_email? and valid_key? and within_time?
  end

  defp hash(key), do: :crypto.hash(:sha256, key)
end

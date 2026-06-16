defmodule Hexpm.Accounts.AccountDeletionRequest do
  use Hexpm.Schema

  schema "account_deletion_requests" do
    field :key, :string
    field :primary_email, :string
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(request, user) do
    change(request, %{
      key: Auth.gen_key(),
      primary_email: User.email(user, :primary)
    })
    |> unique_constraint(:user_id)
  end

  def can_confirm?(request, user, key) do
    valid_user? = request.user_id == user.id
    valid_email? = User.email(user, :primary) == request.primary_email
    valid_key? = !!(request.key && Hexpm.Utils.secure_check(request.key, key))
    within_time? = Hexpm.Utils.within_last_day?(request.inserted_at)

    valid_user? and valid_email? and valid_key? and within_time?
  end
end

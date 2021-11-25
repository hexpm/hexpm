defmodule Hexpm.Accounts.WebAuthRequest do
  use Hexpm.Schema

  @moduledoc false

  # See `lib/hexpm/accounts/web_auth.ex` for an explanation of the terminology used.

  @scopes ["read", "write"]

  schema "requests" do
    field :device_code, :string
    field :user_code, :string
    field :scope, :string
    field :verified, :boolean, default: false
    belongs_to :user, Hexpm.Accounts.User
    field :audit, :string
  end

  def create(request, params \\ %{}) do
    request
    |> cast(params, [:device_code, :user_code, :scope])
    |> validate_inclusion(:scope, @scopes)
    |> validate_required([:device_code, :user_code, :scope, :verified])
    |> unique_constraint([:device_code, :user_code])
  end

  def verify(request, user, audit) do
    request
    |> change()
    |> put_change(:audit, audit)
    |> put_change(:verified, true)
    |> put_assoc(:user, user)
  end
end

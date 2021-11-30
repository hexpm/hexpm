defmodule Hexpm.Accounts.WebAuthRequest do
  use Hexpm.Schema

  @moduledoc false

  alias Hexpm.Accounts.Keys

  # See `lib/hexpm/accounts/web_auth.ex` for an explanation of the terminology used.

  @scopes ["read", "write"]
  @key_permission %{domain: "api", resource: nil}
  @key_params %{name: nil, permissions: [@key_permission]}

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

  def access_key(request) do
    user = request.user

    audit = {user, request.audit}

    scope = request.scope
    device_code = request.device_code
    name = "Web Auth #{device_code} key"

    key_params = %{@key_params | name: name}
    key_params = %{key_params | permissions: [%{@key_permission | resource: scope}]}

    Multi.new()
    |> Multi.run(:key_gen, fn _repo, _changes -> Keys.create(user, key_params, audit: audit) end)
    |> Multi.delete(:delete, request)
  end
end

defmodule Hexpm.Accounts.WebAuthRequest do
  use Hexpm.Schema

  @moduledoc false

  alias Hexpm.Accounts.Keys

  # See `lib/hexpm/accounts/web_auth.ex` for an explanation of the terminology used.

  @key_permission %{domain: "api", resource: nil}
  @key_params %{name: nil, permissions: [@key_permission]}

  schema "requests" do
    field :device_code, :string
    field :user_code, :string
    field :key_name, :string
    field :verified, :boolean, default: false
    belongs_to :user, Hexpm.Accounts.User
    field :audit, :string
  end

  def create(request, params \\ %{}) do
    request
    |> cast(params, [:device_code, :user_code, :key_name])
    |> validate_required([:device_code, :user_code, :key_name, :verified])
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

    key_name = request.key_name

    key_params = %{@key_params | name: key_name}

    write_key = %{key_params | permissions: [%{@key_permission | resource: "write"}]}
    read_key = %{key_params | permissions: [%{@key_permission | resource: "read"}]}

    Multi.new()
    |> Multi.run(:write_key_gen, fn _, _ -> Keys.create(user, write_key, audit: audit) end)
    |> Multi.run(:read_key_gen, fn _, _ -> Keys.create(user, read_key, audit: audit) end)
    |> Multi.delete(:delete, request)
  end
end

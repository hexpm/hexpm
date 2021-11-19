defmodule Hexpm.Accounts.WebAuth do
  use Hexpm.Schema

  @moduledoc false

  # A pool for storing and validating web auth requests.

  alias Hexpm.Accounts.WebAuth
  alias Hexpm.Repo

  alias Hexpm.Accounts.Keys

  # `device_code` refers to the code assigned to a client to identify it
  # `user_code` refers to the code the user enters to authorize a client
  # `scope` refers to the permissions granted to a key
  # `scopes` refers to the list of scopes that are allowed in a web auth request

  @scopes ["read", "write"]

  # `key_permission` is the default permissions given to generate a hex api key
  # `key_params` is the default params to generate a hex api key

  @key_permission %{domain: "api", resource: nil}
  @key_params %{name: nil, permissions: [@key_permission]}

  schema "requests" do
    field :device_code, :string
    field :user_code, :string
    field :scope, :string
    field :verified, :boolean
    field :user_id, :integer
    field :audit, :string
  end

  def changeset(request, params \\ %{}) do
    request
    |> cast(params, [:device_code, :user_code, :scope, :verified, :user_id, :audit])
    |> validate_inclusion(:scope, @scopes)
    |> validate_required([:device_code, :user_code, :scope, :verified])
    |> unique_constraint([:device_code, :user_code])
  end

  @doc """
  Adds a web auth request to the pool and returns the response.

  ## Params

    - `scope` - Scope of the key to be generated. One of read and write.
  """

  def get_code(scope) do
    device_code = "foo"
    user_code = "bar"

    request = %{
      device_code: device_code,
      user_code: user_code,
      scope: scope,
      verified: false
    }

    case changeset(%WebAuth{}, request) |> Repo.insert() do
      {:ok, _req} ->
        %{
          device_code: device_code,
          user_code: user_code
        }

      error ->
        error
    end
  end

  @doc """
  Submits a verification request to the pool and returns the response.

  ## Params

    - `user` - The user for whom the key should be generated.
    - `user_code` - The user code entered by that user.
    - `audit` - Audit data for generating the key.
  """
  def submit(user, user_code, audit) do
    request = WebAuth |> Repo.get_by(user_code: user_code)

    if request do
      {_user, audit_con} = audit

      change = %{verified: true, user_id: user.id, audit: audit_con}

      changeset(request, change) |> Repo.update()
    else
      {:error, "invalid user code"}
    end
  end

  @doc """
  Returns the key of a verified request and deletes the request.

  ## Params

  - `device_code` - The device code assigned to the client
  """
  def access_key(device_code) do
    request = WebAuth |> Repo.get_by(device_code: device_code)

    case request do
      r when r.verified == true ->
        user = Repo.get(Hexpm.Accounts.User, request.user_id)

        audit = {user, request.audit}

        scope = request.scope
        device_code = request.device_code
        name = "Web Auth #{device_code} key"

        # Add name
        key_params = %{@key_params | name: name}
        # Add permissions
        key_params = %{key_params | permissions: [%{@key_permission | resource: scope}]}

        case Keys.create(user, key_params, audit: audit) do
          {:ok, %{key: key}} ->
            Repo.delete(request)

            key

          error ->
            error
        end

      r when r.verified == false ->
        {:error, "request to be verified"}

      nil ->
        {:error, "invalid device code"}
    end
  end
end

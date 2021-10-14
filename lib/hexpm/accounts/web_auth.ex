defmodule Hexpm.Accounts.WebAuth do
  use Hexpm.Schema

  @moduledoc false

  # A pool for storing and validating web auth requests.

  alias Hexpm.Accounts.WebAuth
  alias Hexpm.Repo

  alias HexpmWeb.Router.Helpers, as: Routes
  alias Hexpm.Accounts.Keys
  alias Hexpm.Accounts.Key
  import Phoenix.ConnTest, only: [build_conn: 0]

  # `device_code` refers to the code assigned to a client to identify it
  # `user_code` refers to the code the user enters to authorize a client
  # `verification_uri` refers to the url opened in the browser
  # `access_key_uri` refers to the url the client polls
  # `verification_expires_in` refers to the time a web auth request is stored in seconds
  # `key_access_expires_in` refers to the time a key in stored in seconds
  # `access_key` refers to a key that the user/organization can use
  # `scope` refers to the permissions granted to a key
  # `scopes` refers to the list of scopes that are allowed in a web auth request

  @verification_uri "https://hex.pm" <> Routes.web_auth_path(build_conn(), :show)
  @access_key_uri "https://hex.pm" <> Routes.web_auth_path(build_conn(), :access_key)
  @verification_expires_in 900
  @key_access_expires_in 900
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

    embeds_one :key, Key
  end

  def changeset(request, params \\ %{}) do
    request
    |> cast(params, [:device_code, :user_code, :scope, :verified])
    |> validate_inclusion(:scope, @scopes)
    |> validate_required([:device_code, :user_code, :scope, :verified])
    |> unique_constraint([:device_code, :user_code])
  end

  def submit_changeset(request, key, user, params \\ %{}) do
    request
    |> changeset(params)
    |> put_embed(:key, key)

    # |> cast_embed(:key, with: &Key.changeset(&2, user, Map.from_struct(&1)))
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

    case WebAuth.changeset(%WebAuth{}, request) |> Repo.insert() do
      {:ok, _req} ->
        %{
          device_code: device_code,
          user_code: user_code,
          verification_uri: @verification_uri,
          access_key_uri: @access_key_uri,
          verification_expires_in: @verification_expires_in,
          key_access_expires_in: @key_access_expires_in
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
    scope = request.scope
    device_code = request.device_code

    name = "Web Auth #{device_code} key"
    # Add name
    key_params = %{@key_params | name: name}
    # Add permissions
    key_params = %{key_params | permissions: [%{@key_permission | resource: scope}]}

    case Keys.create(user, key_params, audit: audit) do
      {:ok, %{key: key}} ->
        change = %{verified: true, key: key}

        submit_changeset(request, key, user, change)
        |> IO.inspect()
        |> Repo.update()

      error ->
        error
    end
  end

  def access_key(params) do
    ""
  end
end

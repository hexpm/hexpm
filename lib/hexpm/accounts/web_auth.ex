defmodule Hexpm.Accounts.WebAuth do
  use Hexpm.Context

  @moduledoc false

  import Ecto.Query

  alias Hexpm.Accounts.WebAuthRequest
  alias Hexpm.Utils

  # `device_code` refers to the code assigned to a client to identify it
  # `user_code` refers to the code the user enters to authorize a client
  # `name` refers to the name given to a key
  # `scopes` refers to the list of scopes that are allowed in a web auth request
  # `key_permission` is the default permissions given to generate a hex api key
  # `key_params` is the default params to generate a hex api key

  @key_permission %{domain: "api", resource: nil}
  @key_params %{name: nil, permissions: [@key_permission]}

  @doc """
  Adds a web auth request to the pool and returns the response.

  ## Params

    - `name` - Name of the keys to be generated.
  """

  def get_code(key_name) do
    device_code =
      32
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    user_code =
      5
      |> :crypto.strong_rand_bytes()
      |> Base.hex_encode32(padding: false)
      |> String.split_at(4)
      |> then(fn {x, y} -> x <> "-" <> y end)

    params = %{
      device_code: device_code,
      user_code: user_code,
      key_name: key_name
    }

    changeset = WebAuthRequest.create(%WebAuthRequest{}, params)

    with {:ok, _} <- Repo.insert(changeset) do
      {:ok, %{device_code: device_code, user_code: user_code}}
    end
  end

  @doc """
  Submits a verification request to the pool and returns the response.

  ## Params

    - `user` - The user for whom the key should be generated.
    - `user_code` - The user code entered by that user.
  """
  def submit(user, user_code) do
    request =
      WebAuthRequest
      |> where([r], r.inserted_at >= ^Utils.datetime_utc_yesterday())
      |> where(user_code: ^user_code)
      |> Repo.one()
      |> Repo.preload(:user)

    if request do
      request
      |> WebAuthRequest.verify(user)
      |> Repo.update()
    else
      {:error, "invalid user code"}
    end
  end

  @doc """
  Returns the keys of a verified request and deletes the request.

  ## Params

  - `device_code` - The device code assigned to the client
  - `user_agent` - The user agent for the audit for generating the keys
  """
  def access_key(device_code, user_agent) do
    request =
      WebAuthRequest
      |> where([r], r.inserted_at >= ^Utils.datetime_utc_yesterday())
      |> where(device_code: ^device_code)
      |> Repo.one()
      |> Repo.preload(:user)

    case request do
      r when r.verified ->
        user = request.user

        audit = {user, user_agent}

        key_name = request.key_name

        write_key_params = %{@key_params | name: key_name <> "-write-WebAuth"}
        read_key_params = %{@key_params | name: key_name <> "-read-WebAuth"}

        write_key = %{write_key_params | permissions: [%{@key_permission | resource: "write"}]}
        read_key = %{read_key_params | permissions: [%{@key_permission | resource: "read"}]}

        result =
          Multi.new()
          |> Multi.run(:write_key_gen, fn _, _ -> Keys.create(user, write_key, audit: audit) end)
          |> Multi.run(:read_key_gen, fn _, _ -> Keys.create(user, read_key, audit: audit) end)
          |> Multi.delete(:delete, request)
          |> Repo.transaction()

        case result do
          {:ok, %{write_key_gen: %{key: write_key}, read_key_gen: %{key: read_key}}} ->
            %{write_key: write_key, read_key: read_key}

          {:error, _, _, _} ->
            {:error, "key generation failed"}
        end

      r when not r.verified ->
        {:error, "request to be verified"}

      nil ->
        {:error, "invalid device code"}
    end
  end
end

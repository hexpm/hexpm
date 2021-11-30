defmodule Hexpm.Accounts.WebAuth do
  use Hexpm.Context

  @moduledoc false

  # A pool for storing and validating web auth requests.

  alias Hexpm.Accounts.WebAuthRequest

  # `device_code` refers to the code assigned to a client to identify it
  # `user_code` refers to the code the user enters to authorize a client
  # `scope` refers to the permissions granted to a key
  # `scopes` refers to the list of scopes that are allowed in a web auth request
  # `key_permission` is the default permissions given to generate a hex api key
  # `key_params` is the default params to generate a hex api key

  @doc """
  Adds a web auth request to the pool and returns the response.

  ## Params

    - `scope` - Scope of the key to be generated. One of read and write.
  """

  def get_code(scope) do
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
      scope: scope
    }

    changeset = WebAuthRequest.create(%WebAuthRequest{}, params)

    with {:ok, _} <- Repo.insert(changeset) do
      {:ok, %{device_code: device_code, user_code: user_code}}
    else
      {:error, _changeset} -> {:error, "invalid scope"}
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
    request =
      WebAuthRequest
      |> Repo.get_by(user_code: user_code)
      |> Repo.preload(:user)

    if request do
      {_user, audit_con} = audit

      WebAuthRequest.verify(request, user, audit_con) |> Repo.update()
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
    request =
      WebAuthRequest
      |> Repo.get_by(device_code: device_code)
      |> Repo.preload(:user)

    case request do
      r when r.verified ->
        result =
          request
          |> WebAuthRequest.access_key()
          |> Repo.transaction()

        case result do
          {:ok, %{key_gen: %{key: key}}} ->
            key

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

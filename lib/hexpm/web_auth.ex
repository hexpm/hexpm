defmodule Hexpm.WebAuth do
  use GenServer

  @moduledoc false

  # A pool for storing and validating web auth requests.

  alias HexpmWeb.Router.Helpers, as: Routes
  alias Hexpm.Accounts.Keys
  import Phoenix.ConnTest, only: [build_conn: 0]

  @name __MODULE__

  # `device_code` refers to the code assigned to a client to identify it
  # `user_code` refers to the code the user enters to authorize a client
  # `verification_uri` refers to the url opened in the browser
  # `access_token_uri` refers to the url the client polls
  # `verification_expires_in` refers to the time a web auth request is stored in seconds
  # `token_access_expires_in` refers to the time an access token in stored in seconds
  # `access_token` refers to a key that the user/organization can use
  # `scope` refers to the permissions granted to an access token
  # `scopes` refers to the list of scopes that are allowed in a web auth request

  @verification_uri "https://hex.pm" <> Routes.web_auth_path(build_conn(), :show)
  @access_token_uri "https://hex.pm" <> Routes.web_auth_path(build_conn(), :access_token)
  @verification_expires_in 900
  @token_access_expires_in 900
  @scopes ["read", "write"]

  # `key_permission` is the default permissions given to generate a hex api key
  # `key_params` is the default params to generate a hex api key

  @key_permission %{domain: "api", resource: nil}
  @key_params %{name: nil, permissions: [@key_permission]}

  # Client interface

  @doc """
  Starts the GenServer from a Supervison tree

  ## Options

   - `:name` - The name the Web Auth pool is locally registered as. The default is `Hexpm.WebAuth`.
   - `:verification_uri` - The URI the user enters the user code. By default, it is taken from the Router.
   - `:access_token_uri` - The URI the client polls for the access token. By default, it is taken from the Router.
   - `:verification_expires_in` - The time a web auth request is stored in memory. The default is 15 minutes (900 secs).
   - `:token_access_expires_in` - The time an access token is stored in memory. The default is 15 minutes (900 secs).
  """
  def start_link(opts) do
    name = opts[:name] || @name
    verification_uri = opts[:verification_uri] || @verification_uri
    access_token_uri = opts[:access_token_uri] || @access_token_uri
    verification_expires_in = opts[:verification_expires_in] || @verification_expires_in
    token_access_expires_in = opts[:token_access_expires_in] || @token_access_expires_in

    GenServer.start_link(
      __MODULE__,
      %{
        verification_uri: verification_uri,
        access_token_uri: access_token_uri,
        verification_expires_in: verification_expires_in,
        token_access_expires_in: token_access_expires_in
      },
      name: name
    )
  end

  @doc """
  Adds a web auth request to the pool and returns the response.

  ## Function Params

    - `server` - The PID or locally registered name of the GenServer.
    - `params` - The parameters of a web auth request.

  ## Request Params

    - `scope` - Scope of the key to be generated. One of read and write.
  """
  def get_code(server \\ @name, params)

  def get_code(server, %{"scope" => scope}) when scope in @scopes do
    GenServer.call(server, {:get_code, scope, server})
  end

  def get_code(_server, %{"scope" => _scope}) do
    {:error, "invalid scope"}
  end

  def get_code(_server, _params) do
    {:error, "invalid parameters"}
  end

  @doc """
  Submits a verification request to the pool and returns the response.

  ## Params

   - `server` - The PID or locally registered name of the GenServer
   - `params` - The parameters of a verification request.
  """
  def submit_code(server \\ @name, params)

  def submit_code(server, %{"user" => user, "user_code" => code, "audit" => audit}) do
    state = GenServer.call(server, {:get_state, server})

    if Enum.any?(state.requests, fn x -> x.user_code == code end) do
      GenServer.call(server, {:submit_code, user, code, audit, server})
    else
      {:error, "invalid user_code"}
    end
  end

  def submit_code(_server, _params) do
    {:error, "invalid parameters"}
  end

  # Server side code

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       verification_uri: opts.verification_uri,
       access_token_uri: opts.access_token_uri,
       verification_expires_in: opts.verification_expires_in,
       token_access_expires_in: opts.token_access_expires_in,
       requests: [],
       access_tokens: []
     }}
  end

  @impl GenServer
  def handle_call({:get_code, scope, server}, _, state) do
    {response, new_state} = code(scope, server, state)
    {:reply, response, new_state}
  end

  @impl GenServer
  def handle_call({:submit_code, user, user_code, audit, _server}, _, state) do
    {response, new_state} = submit(user, user_code, audit, state)
    {:reply, response, new_state}
  end

  @impl GenServer
  def handle_call({:get_state, _}, _, state) do
    {:reply, state, state}
  end

  # Helper functions

  defp code(scope, server, state) do
    device_code = "foo"
    user_code = "bar"

    response = %{
      device_code: device_code,
      user_code: user_code,
      verification_uri: state.verification_uri,
      access_token_uri: state.access_token_uri,
      verification_expires_in: state.verification_expires_in,
      token_access_expires_in: state.token_access_expires_in
    }

    request = %{device_code: device_code, user_code: user_code, scope: scope}

    case state.verification_expires_in do
      0 ->
        send(server, {:delete_request, device_code})

      t ->
        _ =
          Process.send_after(
            server,
            {:delete_request, device_code},
            t
          )
    end

    {response, %{state | requests: [request | state.requests]}}
  end

  defp submit(user, user_code, audit, state) do
    request = Enum.find(state.requests, fn x -> x.user_code == user_code end)
    scope = request.scope
    device_code = request.device_code

    name = "Web Auth #{device_code} key"
    # Add name
    key_params = %{@key_params | name: name}
    # Add permissions
    key_params = %{key_params | permissions: [%{@key_permission | resource: scope}]}

    case Keys.create(user, key_params, audit: audit) do
      {:ok, %{key: key}} ->
        token = %{device_code: device_code, access_token: key, scope: scope}

        requests = List.delete(state.requests, request)
        access_tokens = [state.access_tokens | token]

        new_state = %{state | requests: requests}
        new_state = %{new_state | access_tokens: access_tokens}

        {:ok, new_state}

      {:error, :key, changeset, _} ->
        {{:error, changeset}, state}
    end
  end
end

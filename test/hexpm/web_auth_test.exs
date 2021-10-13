defmodule Hexpm.WebAuthTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.WebAuth

  @scope "write"

  describe "start_link/1" do
    test "correctly starts a registered GenServer", config do
      start_supervised!({WebAuth, name: config.test})

      # Verify Process is running
      assert Process.whereis(config.test)
    end
  end

  describe "get_code/2" do
    setup :start_server

    test "returns a valid response on valid scope", config do
      for scope <- ["write", "read"] do
        response = WebAuth.get_code(config.test, %{"scope" => scope})

        assert response.device_code
        assert response.user_code
        assert response.verification_uri
        assert response.access_token_uri
        assert response.verification_expires_in
        assert response.token_access_expires_in
      end
    end

    test "returns an error on invalid scope", config do
      assert WebAuth.get_code(config.test, %{"scope" => "foo"}) == {:error, "invalid scope"}
    end

    test "returns an error on invalid parameters", config do
      assert WebAuth.get_code(config.test, "foo") == {:error, "invalid parameters"}
    end
  end

  test "deletes request after `verification_expires_in` seconds", c do
    start_supervised!({WebAuth, name: c.test, verification_expires_in: 0})

    c =
      c
      |> login
      |> get_code

    audit_data = audit_data(c.user)

    params = %{
      "user" => c.user,
      "user_code" => c.request.user_code,
      "audit" => audit_data
    }

    assert WebAuth.submit_code(c.test, params) == {:error, "invalid user_code"}
  end

  describe "submit/2" do
    setup [:start_server, :allow_db, :login, :get_code]

    test "returns ok on valid params", c do
      audit_data = audit_data(c.user)

      params = %{
        "user" => c.user,
        "user_code" => c.request.user_code,
        "audit" => audit_data
      }

      assert WebAuth.submit_code(c.test, params) == :ok
    end

    test "returns an error on invalid params", c do
      assert WebAuth.submit_code(c.test, %{foo: "bar"}) == {:error, "invalid parameters"}
    end

    test "returns an error on invalid user_code", c do
      audit_data = audit_data(c.user)

      params = %{
        "user" => c.user,
        "user_code" => "bad code",
        "audit" => audit_data
      }

      assert WebAuth.submit_code(c.test, params) == {:error, "invalid user_code"}
    end
  end

  describe "access_token/2" do
    setup [:start_server, :allow_db, :login, :get_code]

    test "returns a key on valid request", c do
      _ = submit_code(c)
      params = %{"device_code" => c.request.device_code}

      response = WebAuth.access_token(c.test, params)

      assert response.access_token
    end

    test "returns an error on unverified request", c do
      params = %{"device_code" => c.request.device_code}

      assert WebAuth.access_token(c.test, params) == {:error, "verification pending"}
    end

    test "returns an error on invalid device code", c do
      params = %{"device_code" => "bad code"}

      assert WebAuth.access_token(c.test, params) == {:error, "invalid device code"}
    end

    test "returns an error on invalid params", c do
      assert WebAuth.access_token(c.test, "bad params") == {:error, "invalid parameters"}
    end
  end

  def start_server(config) do
    start_supervised!({WebAuth, name: config.test})
    :ok
  end

  def allow_db(config) do
    allow = Process.whereis(config.test)
    :ok = Ecto.Adapters.SQL.Sandbox.allow(Hexpm.RepoBase, self(), allow)

    :ok
  end

  def login(context) do
    user = insert(:user)
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: user)

    Map.merge(context, %{user: user, organization: organization})
  end

  def get_code(context) do
    request = WebAuth.get_code(context.test, %{"scope" => @scope})

    Map.merge(context, %{request: request})
  end

  def submit_code(c) do
    audit_data = audit_data(c.user)

    params = %{
      "user" => c.user,
      "user_code" => c.request.user_code,
      "audit" => audit_data
    }

    _ok = WebAuth.submit_code(c.test, params)

    c
  end
end

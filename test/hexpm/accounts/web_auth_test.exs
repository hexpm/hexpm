defmodule Hexpm.Accounts.WebAuthTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.WebAuth

  @scope "write"

  describe "get_code/1" do
    test "returns a valid response on valid scope" do
      for scope <- ["write", "read"] do
        response = WebAuth.get_code(scope)

        assert response.device_code
        assert response.user_code
        assert response.verification_uri
        assert response.access_key_uri
        assert response.verification_expires_in
      end
    end

    test "returns an error on invalid scope" do
      {status, _changeset} = WebAuth.get_code("foo")
      assert status == :error
    end
  end

  describe "submit/3" do
    setup [:get_code, :login]

    test "returns ok on valid params", c do
      audit_data = audit_data(c.user)

      {status, _changeset} = WebAuth.submit(c.user, c.request.user_code, audit_data)
      assert status == :ok
    end

    test "returns error on invalid user code", c do
      audit_data = audit_data(c.user)

      assert WebAuth.submit(c.user, "bad_code", audit_data) == {:error, "invalid user code"}
    end
  end

  describe "access_key/1" do
    setup [:get_code, :login]

    test "returns a key on valid device code", c do
      submit_code(c)

      key =
        c.request.device_code
        |> WebAuth.access_key()

      assert key.__struct__ == Hexpm.Accounts.Key
    end

    test "returns an error on unverified request", c do
      key =
        c.request.device_code
        |> WebAuth.access_key()

      assert key == {:error, "request to be verified"}
    end

    test "returns an error on invalid device code" do
      key =
        "bad code"
        |> WebAuth.access_key()

      assert key == {:error, "invalid device code"}
    end

    test "deletes request after user has accessed", c do
      submit_code(c)

      c.request.device_code |> WebAuth.access_key()

      second_call = c.request.device_code |> WebAuth.access_key()

      assert second_call == {:error, "invalid device code"}
    end
  end

  def get_code(context) do
    request = WebAuth.get_code(@scope)

    Map.merge(context, %{request: request})
  end

  def login(context) do
    user = insert(:user)
    organization = insert(:organization)
    insert(:organization_user, organization: organization, user: user)

    Map.merge(context, %{user: user, organization: organization})
  end

  def submit_code(c) do
    audit_data = audit_data(c.user)
    WebAuth.submit(c.user, c.request.user_code, audit_data)

    c
  end
end

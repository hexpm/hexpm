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
        assert response.key_access_expires_in
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

      assert WebAuth.submit(c.user, c.request.user_code, audit_data) == :ok
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
end

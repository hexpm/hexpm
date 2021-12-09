defmodule Hexpm.Accounts.WebAuthTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.WebAuth

  @key_name "test-key"

  describe "get_code/1" do
    test "returns a valid response" do
      {:ok, response} = WebAuth.get_code(@key_name)

      assert response.device_code
      assert response.user_code
    end

    test "returns unique codes" do
      {:ok, response1} = WebAuth.get_code(@key_name)
      {:ok, response2} = WebAuth.get_code(@key_name)

      assert response1.device_code != response2.device_code
      assert response1.user_code != response2.user_code
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

    test "returns keys on valid device code", c do
      submit_code(c)

      keys = WebAuth.access_key(c.request.device_code)

      assert %{write_key: %Hexpm.Accounts.Key{}, read_key: %Hexpm.Accounts.Key{}} = keys
    end

    test "returns an error on unverified request", c do
      response = WebAuth.access_key(c.request.device_code)

      assert response == {:error, "request to be verified"}
    end

    test "returns an error on invalid device code" do
      response = WebAuth.access_key("bad code")

      assert response == {:error, "invalid device code"}
    end

    test "deletes request after user has accessed", c do
      submit_code(c)

      WebAuth.access_key(c.request.device_code)
      second_call = WebAuth.access_key(c.request.device_code)

      assert second_call == {:error, "invalid device code"}
    end
  end

  def get_code(context) do
    {:ok, request} = WebAuth.get_code(@key_name)

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

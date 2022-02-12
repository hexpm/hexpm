defmodule Hexpm.Accounts.WebAuthTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{WebAuth, WebAuthRequest}
  alias Hexpm.Utils

  alias Ecto.Changeset

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
      {status, _changeset} = WebAuth.submit(c.user, c.request.user_code)
      assert status == :ok
    end

    test "returns error on invalid user code", c do
      assert WebAuth.submit(c.user, "bad_code") == {:error, "invalid user code"}
    end

    test "returns error on stale request's user code", c do
      make_request_stale(c)

      assert WebAuth.submit(c.user, c.request.user_code) == {:error, "invalid user code"}
    end
  end

  describe "access_key/1" do
    setup [:get_code, :login, :get_audit_user_agent]

    test "returns keys on valid device code", c do
      submit_code(c)

      keys = WebAuth.access_key(c.request.device_code, c.audit_user_agent)

      assert {:ok, %{write_key: %Hexpm.Accounts.Key{}, read_key: %Hexpm.Accounts.Key{}}} = keys
    end

    test "returns an error on unverified request", c do
      response = WebAuth.access_key(c.request.device_code, c.audit_user_agent)

      assert response == {:error, "request to be verified"}
    end

    test "returns an error on invalid device code", c do
      response = WebAuth.access_key("bad code", c.audit_user_agent)

      assert response == {:error, "invalid device code"}
    end

    test "returns an error on state request's device code", c do
      make_request_stale(c)
      response = WebAuth.access_key(c.request.device_code, c.audit_user_agent)

      assert response == {:error, "invalid device code"}
    end

    test "deletes request after user has accessed", c do
      submit_code(c)

      WebAuth.access_key(c.request.device_code, c.audit_user_agent)
      second_call = WebAuth.access_key(c.request.device_code, c.audit_user_agent)

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
    WebAuth.submit(c.user, c.request.user_code)

    c
  end

  def get_audit_user_agent(c) do
    c.user
    |> audit_data
    |> elem(1)
    |> then(&Map.put_new(c, :audit_user_agent, &1))
  end

  def make_request_stale(c) do
    Repo.get_by(WebAuthRequest, user_code: c.request.user_code)
    |> Changeset.change(inserted_at: Utils.datetime_utc_yesterday())
    |> Repo.update()
  end
end

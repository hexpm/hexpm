defmodule Hexpm.OAuth.DeviceCodeTest do
  use Hexpm.DataCase, async: true

  import Ecto.Changeset, only: [get_field: 2]

  alias Hexpm.OAuth.{DeviceCode, Clients}

  describe "changeset/2" do
    test "validates required fields" do
      changeset = DeviceCode.changeset(%DeviceCode{}, %{})

      assert %{
               device_code: "can't be blank",
               user_code: "can't be blank",
               verification_uri: "can't be blank",
               client_id: "can't be blank",
               expires_at: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates interval is positive" do
      changeset =
        DeviceCode.changeset(%DeviceCode{}, %{
          device_code: "device123",
          user_code: "USER-CODE",
          verification_uri: "https://example.com/device",
          client_id: Clients.generate_client_id(),
          expires_at: DateTime.utc_now(),
          interval: 0
        })

      assert %{interval: "must be greater than 0"} = errors_on(changeset)
    end

    test "creates valid changeset with all fields" do
      attrs = %{
        device_code: "device123",
        user_code: "USER-CODE",
        verification_uri: "https://example.com/device",
        verification_uri_complete: "https://example.com/device?user_code=USER-CODE",
        client_id: "test_client",
        expires_at: DateTime.utc_now(),
        interval: 5,
        scopes: ["api", "api:read"]
      }

      changeset = DeviceCode.changeset(%DeviceCode{}, attrs)
      assert changeset.valid?
    end

    test "sets default values" do
      attrs = %{
        device_code: "device123",
        user_code: "USER-CODE",
        verification_uri: "https://example.com/device",
        client_id: "test_client",
        expires_at: DateTime.utc_now()
      }

      changeset = DeviceCode.changeset(%DeviceCode{}, attrs)
      assert changeset.valid?

      device_code = Ecto.Changeset.apply_changes(changeset)
      assert device_code.interval == 5
      assert device_code.status == "pending"
      assert device_code.scopes == []
    end
  end

  describe "authorize_changeset/2" do
    test "creates changeset to authorize device code" do
      user = insert(:user)
      device_code = %DeviceCode{status: "pending"}

      changeset = DeviceCode.authorize_changeset(device_code, user)

      assert get_field(changeset, :status) == "authorized"
      assert get_field(changeset, :user_id) == user.id
    end
  end

  describe "deny_changeset/1" do
    test "creates changeset to deny device code" do
      device_code = %DeviceCode{status: "pending"}

      changeset = DeviceCode.deny_changeset(device_code)

      assert get_field(changeset, :status) == "denied"
    end
  end

  describe "expire_changeset/1" do
    test "creates changeset to expire device code" do
      device_code = %DeviceCode{status: "pending"}

      changeset = DeviceCode.expire_changeset(device_code)

      assert get_field(changeset, :status) == "expired"
    end
  end

  describe "edge cases and boundaries" do
    test "handles all valid status transitions" do
      user = insert(:user)

      device_code = %DeviceCode{status: "pending"}

      auth_changeset = DeviceCode.authorize_changeset(device_code, user)
      assert get_field(auth_changeset, :status) == "authorized"

      deny_changeset = DeviceCode.deny_changeset(device_code)
      assert get_field(deny_changeset, :status) == "denied"

      expire_changeset = DeviceCode.expire_changeset(device_code)
      assert get_field(expire_changeset, :status) == "expired"
    end
  end
end

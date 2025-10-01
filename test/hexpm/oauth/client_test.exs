defmodule Hexpm.OAuth.ClientTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.OAuth.{Client, Clients}

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Client.changeset(%Client{}, %{})

      assert %{
               client_id: "can't be blank",
               name: "can't be blank",
               client_type: "can't be blank"
             } = errors_on(changeset)
    end

    test "validates client_type inclusion" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: Clients.generate_client_id(),
          name: "Test Client",
          client_type: "invalid"
        })

      assert %{client_type: "is invalid"} = errors_on(changeset)
    end

    test "validates grant types" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: Clients.generate_client_id(),
          name: "Test Client",
          client_type: "public",
          allowed_grant_types: ["invalid_grant", "authorization_code"]
        })

      assert %{allowed_grant_types: "contains invalid grant types: invalid_grant"} =
               errors_on(changeset)
    end

    test "validates scopes" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: Clients.generate_client_id(),
          name: "Test Client",
          client_type: "public",
          allowed_scopes: ["invalid_scope", "api"]
        })

      assert %{allowed_scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "requires client_secret for confidential clients" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: Clients.generate_client_id(),
          name: "Test Client",
          client_type: "confidential"
        })

      assert %{client_secret: "is required for confidential clients"} = errors_on(changeset)
    end

    test "allows public clients without client_secret" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: Clients.generate_client_id(),
          name: "Test Client",
          client_type: "public"
        })

      refute changeset.errors[:client_secret]
    end

    test "creates valid changeset with all fields" do
      attrs = %{
        client_id: "test_client",
        name: "Test Client",
        client_type: "confidential",
        client_secret: "secret",
        allowed_grant_types: ["authorization_code", "refresh_token"],
        redirect_uris: ["https://example.com/callback"],
        allowed_scopes: ["api", "api:read"]
      }

      changeset = Client.changeset(%Client{}, attrs)
      assert changeset.valid?
    end
  end

  describe "build/1" do
    test "builds client with valid attributes" do
      attrs = %{
        client_id: "test_client",
        name: "Test Client",
        client_type: "public"
      }

      changeset = Client.build(attrs)
      assert changeset.valid?
    end
  end
end

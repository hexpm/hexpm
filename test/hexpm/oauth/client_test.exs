defmodule Hexpm.OAuth.ClientTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.OAuth.Client

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
          client_id: "test_client",
          name: "Test Client",
          client_type: "invalid"
        })

      assert %{client_type: "is invalid"} = errors_on(changeset)
    end

    test "validates grant types" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: "test_client",
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
          client_id: "test_client",
          name: "Test Client",
          client_type: "public",
          allowed_scopes: ["invalid_scope", "api"]
        })

      assert %{allowed_scopes: "contains invalid scopes: invalid_scope"} = errors_on(changeset)
    end

    test "requires client_secret for confidential clients" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: "test_client",
          name: "Test Client",
          client_type: "confidential"
        })

      assert %{client_secret: "is required for confidential clients"} = errors_on(changeset)
    end

    test "allows public clients without client_secret" do
      changeset =
        Client.changeset(%Client{}, %{
          client_id: "test_client",
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

  describe "supports_grant_type?/2" do
    test "returns true for allowed grant types" do
      client = %Client{allowed_grant_types: ["authorization_code", "refresh_token"]}

      assert Client.supports_grant_type?(client, "authorization_code")
      assert Client.supports_grant_type?(client, "refresh_token")
    end

    test "returns false for disallowed grant types" do
      client = %Client{allowed_grant_types: ["authorization_code"]}

      refute Client.supports_grant_type?(client, "refresh_token")
      refute Client.supports_grant_type?(client, "urn:ietf:params:oauth:grant-type:device_code")
    end
  end

  describe "supports_scopes?/2" do
    test "returns true when all requested scopes are allowed" do
      client = %Client{allowed_scopes: ["api", "api:read", "api:write"]}

      assert Client.supports_scopes?(client, ["api"])
      assert Client.supports_scopes?(client, ["api", "api:read"])
      assert Client.supports_scopes?(client, ["api:read", "api:write"])
    end

    test "returns false when any requested scope is not allowed" do
      client = %Client{allowed_scopes: ["api", "api:read"]}

      refute Client.supports_scopes?(client, ["api:write"])
      refute Client.supports_scopes?(client, ["api", "repositories"])
      refute Client.supports_scopes?(client, ["invalid_scope"])
    end

    test "returns true for empty scope list" do
      client = %Client{allowed_scopes: ["api"]}

      assert Client.supports_scopes?(client, [])
    end
  end

  describe "valid_redirect_uri?/2" do
    test "returns false when no redirect URIs are configured" do
      client = %Client{redirect_uris: []}

      refute Client.valid_redirect_uri?(client, "https://example.com/callback")
    end

    test "returns true for allowed redirect URIs" do
      client = %Client{
        redirect_uris: ["https://example.com/callback", "https://app.example.com/auth"]
      }

      assert Client.valid_redirect_uri?(client, "https://example.com/callback")
      assert Client.valid_redirect_uri?(client, "https://app.example.com/auth")
    end

    test "returns false for disallowed redirect URIs" do
      client = %Client{redirect_uris: ["https://example.com/callback"]}

      refute Client.valid_redirect_uri?(client, "https://malicious.com/callback")
      refute Client.valid_redirect_uri?(client, "https://example.com/different")
    end
  end

  describe "requires_authentication?/1" do
    test "returns true for confidential clients" do
      client = %Client{client_type: "confidential"}

      assert Client.requires_authentication?(client)
    end

    test "returns false for public clients" do
      client = %Client{client_type: "public"}

      refute Client.requires_authentication?(client)
    end
  end

  describe "authenticate/2" do
    test "validates correct credentials for confidential client" do
      hashed_secret = Bcrypt.hash_pwd_salt("secret123")
      client = %Client{client_secret: hashed_secret}

      assert Client.authenticate(client, "secret123")
    end

    test "rejects incorrect credentials for confidential client" do
      hashed_secret = Bcrypt.hash_pwd_salt("secret123")
      client = %Client{client_secret: hashed_secret}

      refute Client.authenticate(client, "wrong_secret")
      refute Client.authenticate(client, nil)
      refute Client.authenticate(client, "")
    end

    test "always succeeds for public client" do
      client = %Client{client_secret: nil}

      assert Client.authenticate(client, "any_secret")
      assert Client.authenticate(client, nil)
      assert Client.authenticate(client, "")
    end
  end

  describe "generate_client_secret/0" do
    test "generates non-empty string" do
      secret = Client.generate_client_secret()

      assert is_binary(secret)
      assert String.length(secret) > 0
    end

    test "generates unique secrets" do
      secret1 = Client.generate_client_secret()
      secret2 = Client.generate_client_secret()

      assert secret1 != secret2
    end

    test "generates base64url encoded strings" do
      secret = Client.generate_client_secret()

      # Should not contain padding characters
      refute String.contains?(secret, "=")
      # Should be valid base64url (add padding if needed)
      padded_secret = secret <> String.duplicate("=", rem(4 - rem(String.length(secret), 4), 4))
      assert {:ok, _} = Base.url_decode64(padded_secret)
    end
  end

  describe "generate_client_id/0" do
    test "generates non-empty string" do
      client_id = Client.generate_client_id()

      assert is_binary(client_id)
      assert String.length(client_id) > 0
    end

    test "generates unique client IDs" do
      client_id1 = Client.generate_client_id()
      client_id2 = Client.generate_client_id()

      assert client_id1 != client_id2
    end

    test "generates lowercase hex strings" do
      client_id = Client.generate_client_id()

      # Should be 32 characters (16 bytes as hex)
      assert String.length(client_id) == 32
      # Should only contain lowercase hex characters
      assert Regex.match?(~r/^[0-9a-f]+$/, client_id)
    end
  end
end

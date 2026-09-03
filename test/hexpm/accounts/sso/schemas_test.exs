defmodule Hexpm.Accounts.SSO.SchemasTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Connection, Identity, Transaction}

  describe "Connection.credentials_changeset/2" do
    test "bounds the credentials in bytes" do
      assert credentials(issuer: "https://" <> combining_string(2040)).valid?
      assert credentials(client_id: combining_string(1024)).valid?
      assert credentials(client_secret: combining_string(4096)).valid?

      changeset = credentials(issuer: "https://" <> combining_string(2041))
      assert errors_on(changeset).issuer == "should be at most 2048 byte(s)"

      changeset = credentials(client_id: combining_string(1025))
      assert errors_on(changeset).client_id == "should be at most 1024 byte(s)"

      changeset = credentials(client_secret: combining_string(4097))
      assert errors_on(changeset).client_secret == "should be at most 4096 byte(s)"
    end

    defp credentials(overrides) do
      attrs =
        Map.merge(
          %{
            organization_id: 1,
            issuer: "https://idp.example.com",
            client_id: "client",
            client_secret: "secret"
          },
          Map.new(overrides)
        )

      Connection.credentials_changeset(%Connection{}, attrs)
    end
  end

  describe "Identity.changeset/2" do
    test "bounds the subject and provider email in bytes" do
      assert identity(subject: combining_string(255)).valid?
      assert identity(provider_email: combining_string(255)).valid?

      changeset = identity(subject: combining_string(256))
      assert errors_on(changeset).subject == "should be at most 255 byte(s)"

      changeset = identity(provider_email: combining_string(256))
      assert errors_on(changeset).provider_email == "should be at most 255 byte(s)"
    end

    defp identity(overrides) do
      attrs =
        Map.merge(
          %{
            organization_id: 1,
            connection_id: 1,
            user_id: 1,
            issuer: "https://idp.example.com",
            subject: "subject"
          },
          Map.new(overrides)
        )

      Identity.changeset(%Identity{}, attrs)
    end
  end

  describe "Transaction.changeset/2" do
    test "bounds the return path in bytes" do
      assert transaction(return_path: "/" <> combining_string(2047)).valid?

      changeset = transaction(return_path: "/" <> combining_string(2048))
      assert errors_on(changeset).return_path == "should be at most 2048 byte(s)"
    end

    test "bounds the provider claims in bytes" do
      changeset =
        Transaction.consume_changeset(%Transaction{}, %{
          subject: combining_string(256),
          provider_email: combining_string(256)
        })

      assert errors_on(changeset).subject == "should be at most 255 byte(s)"
      assert errors_on(changeset).provider_email == "should be at most 255 byte(s)"
    end

    defp transaction(overrides) do
      attrs =
        Map.merge(
          %{
            connection_id: 1,
            state_hash: "hash",
            nonce: "nonce",
            code_verifier: "verifier",
            kind: "login",
            secret_slot: "active",
            connection_version: 1,
            secret_version: 1,
            redirect_uri: "https://hex.pm/sso/callback",
            expires_at: DateTime.utc_now()
          },
          Map.new(overrides)
        )

      Transaction.changeset(%Transaction{}, attrs)
    end
  end

  describe "allowed_return_path/1" do
    test "drops a path over 2048 bytes" do
      assert SSO.allowed_return_path("/" <> combining_string(2047)) ==
               "/" <> combining_string(2047)

      assert SSO.allowed_return_path("/" <> combining_string(2048)) == nil
    end
  end
end

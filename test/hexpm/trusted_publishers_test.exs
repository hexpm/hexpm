defmodule Hexpm.TrustedPublishersTest do
  use Hexpm.DataCase, async: false
  import Mox

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.TrustedPublishers
  alias Hexpm.TrustedPublisherHelpers

  setup :verify_on_exit!

  setup do
    TrustedPublisherHelpers.ensure_oauth_client()
    TrustedPublisherHelpers.stub_oidc_discovery()

    user = insert(:user)

    package =
      insert(:package,
        package_owners: [build(:package_owner, user: user, level: "full")]
      )

    trusted_publisher =
      insert(:trusted_publisher,
        package: package,
        repository_owner: "acme",
        repository_owner_id: "12345",
        repository_id: "67890",
        repository: "acme/widget",
        workflow: "release.yml"
      )

    %{user: user, package: package, trusted_publisher: trusted_publisher}
  end

  describe "verify_and_mint/2" do
    test "mints a package-scoped token for a matching OIDC JWT", %{package: package} do
      token =
        TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      assert {:ok, access_token} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name,
                 audit: audit_data(insert(:user))
               )

      assert access_token.grant_type == "trusted_publisher"
      assert access_token.scopes == ["package:hexpm/#{package.name}"]
      assert is_binary(access_token.access_token)

      {:ok, claims} = Joken.peek_claims(access_token.access_token)
      assert claims["sub"] == "trusted_publisher:#{access_token.trusted_publisher_id}"
      refute claims["scope"] =~ "api:write"
    end

    test "stores an allowlisted snapshot of the OIDC claims on the minted token", %{
      package: package
    } do
      token =
        TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      assert {:ok, access_token} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )

      reloaded = Repo.get(Hexpm.OAuth.Token, access_token.id)

      assert reloaded.oidc_claims["repository"] == "acme/widget"
      assert reloaded.oidc_claims["workflow_ref"] =~ "acme/widget/.github/workflows/release.yml"
      refute Map.has_key?(reloaded.oidc_claims, "jti")
      refute Map.has_key?(reloaded.oidc_claims, "aud")
    end

    test "writes a mint audit log", %{package: package, trusted_publisher: tp} do
      token =
        TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      assert {:ok, _} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name,
                 audit: %{
                   user: nil,
                   auth_credential: nil,
                   user_agent: "test",
                   remote_ip: "127.0.0.1"
                 }
               )

      log = Repo.get_by!(AuditLog, action: "trusted_publisher.mint")
      assert log.user_id == nil
      assert log.params["subject"] == "trusted_publisher:#{tp.id}"
    end

    test "mints per package when one repository config backs several packages", %{
      package: package,
      trusted_publisher: tp
    } do
      other_package = insert(:package)

      insert(:trusted_publisher,
        package: other_package,
        repository_owner: tp.repository_owner,
        repository_owner_id: tp.repository_owner_id,
        repository_id: tp.repository_id,
        repository: tp.repository,
        workflow: tp.workflow
      )

      first_oidc =
        TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      second_oidc =
        TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      assert {:ok, first} =
               TrustedPublishers.verify_and_mint(first_oidc,
                 repository: "hexpm",
                 package: package.name
               )

      assert {:ok, second} =
               TrustedPublishers.verify_and_mint(second_oidc,
                 repository: "hexpm",
                 package: other_package.name
               )

      assert first.scopes == ["package:hexpm/#{package.name}"]
      assert second.scopes == ["package:hexpm/#{other_package.name}"]

      assert {:error, :token_replayed} =
               TrustedPublishers.verify_and_mint(first_oidc,
                 repository: "hexpm",
                 package: other_package.name
               )
    end

    test "rejects replayed OIDC jti", %{package: package} do
      claims = TrustedPublisherHelpers.github_claims() |> Map.put("jti", "fixed-jti-1")
      token = TrustedPublisherHelpers.sign_oidc_claims(claims)

      assert {:ok, _} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )

      assert {:error, :token_replayed} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects audience mismatch", %{package: package} do
      token =
        TrustedPublisherHelpers.sign_oidc_claims(
          Map.put(TrustedPublisherHelpers.github_claims(), "aud", "wrong")
        )

      assert {:error, :audience_mismatch} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects issuer not in allowlist", %{package: package} do
      token =
        TrustedPublisherHelpers.sign_oidc_claims(
          Map.put(TrustedPublisherHelpers.github_claims(), "iss", "https://evil.example.com")
        )

      assert {:error, :issuer_not_allowed} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects non-string issuer", %{package: package} do
      # Build a token with a non-string iss claim via JOSE.
      claims =
        Map.merge(TrustedPublisherHelpers.github_claims(), %{
          "iss" => 123,
          "aud" => "hexpm",
          "iat" => System.system_time(:second),
          "nbf" => System.system_time(:second) - 30,
          "exp" => System.system_time(:second) + 600,
          "jti" => "bad-iss"
        })

      {_, signed} =
        JOSE.JWT.sign(TrustedPublisherHelpers.rsa_jwk(), %{"alg" => "RS256"}, claims)

      {_, token} = JOSE.JWS.compact(signed)

      assert {:error, :issuer_missing} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects mismatched repository_owner_id", %{package: package} do
      token =
        TrustedPublisherHelpers.sign_oidc_claims(
          TrustedPublisherHelpers.github_claims(repository_owner_id: "99999")
        )

      assert {:error, :no_matching_publisher} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects wrong workflow", %{package: package} do
      token =
        TrustedPublisherHelpers.sign_oidc_claims(
          TrustedPublisherHelpers.github_claims(workflow: "other.yml")
        )

      assert {:error, :no_matching_publisher} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "returns :disabled when feature flag is off", %{package: package} do
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, trusted_publishers: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

      token =
        TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

      assert {:error, :disabled} =
               TrustedPublishers.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end
  end

  describe "create/3" do
    test "resolves immutable ids and stores publisher", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 42}}
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99}}
      end)

      assert {:ok, publisher} =
               TrustedPublishers.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "Acme",
                   "repository" => "Widget",
                   "workflow" => "Release.yml"
                 },
                 audit: audit_data(user)
               )

      assert publisher.repository == "acme/widget"
      assert publisher.repository_owner == "acme"
      assert publisher.workflow == "release.yml"
      assert publisher.repository_owner_id == "42"
      assert publisher.repository_id == "99"
    end

    test "allows the same configuration on several packages", %{user: user} do
      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repository" => "widget",
        "workflow" => "release.yml"
      }

      packages =
        for _ <- 1..2 do
          insert(:package,
            package_owners: [build(:package_owner, user: user, level: "full")]
          )
        end

      expect(Hexpm.HTTP.Mock, :get, 4, fn
        "https://api.github.com/users/acme", _, _ -> {:ok, 200, [], %{"id" => 42}}
        "https://api.github.com/repos/acme/widget", _, _ -> {:ok, 200, [], %{"id" => 99}}
      end)

      for package <- packages do
        assert {:ok, publisher} =
                 TrustedPublishers.create(package, params, audit: audit_data(user))

        assert publisher.package_id == package.id
        assert publisher.repository == "acme/widget"
      end
    end
  end
end

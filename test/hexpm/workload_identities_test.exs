defmodule Hexpm.WorkloadIdentitiesTest do
  use Hexpm.DataCase, async: false
  import Mox
  import Swoosh.TestAssertions

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.WorkloadIdentities
  alias Hexpm.WorkloadIdentityHelpers

  setup :verify_on_exit!

  setup do
    WorkloadIdentityHelpers.stub_oidc_discovery()

    user = insert(:user)

    package =
      insert(:package,
        package_owners: [build(:package_owner, user: user, level: "full")]
      )

    workload_identity =
      insert(:workload_identity,
        package: package,
        repository_owner: "acme",
        repository_owner_id: "12345",
        repository_id: "67890",
        repository: "acme/widget",
        workflow: "release.yml"
      )

    %{user: user, package: package, workload_identity: workload_identity}
  end

  describe "verify_and_mint/2" do
    test "mints a package-scoped token for a matching OIDC JWT", %{package: package} do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, access_token} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name,
                 audit: audit_data(insert(:user))
               )

      assert access_token.grant_type == "workload_identity"
      assert access_token.scopes == ["package:hexpm/#{package.name}"]
      assert access_token.client_id == nil
      assert is_binary(access_token.access_token)

      {:ok, claims} = Joken.peek_claims(access_token.access_token)
      assert claims["sub"] == "workload_identity:#{access_token.workload_identity_id}"
      refute claims["scope"] =~ "api:write"
    end

    test "stores an allowlisted snapshot of the OIDC claims on the minted token", %{
      package: package
    } do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, access_token} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )

      reloaded = Repo.get(Hexpm.OAuth.Token, access_token.id)

      assert %Hexpm.WorkloadIdentities.ClaimsSnapshot{} = reloaded.oidc_claims
      assert reloaded.oidc_claims.repository == "acme/widget"
      assert reloaded.oidc_claims.workflow_ref =~ "acme/widget/.github/workflows/release.yml"
    end

    test "does not write an audit log", %{package: package} do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, _} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )

      assert Repo.aggregate(AuditLog, :count) == 0
    end

    test "mints per package when one repository config backs several packages", %{
      package: package,
      workload_identity: tp
    } do
      other_package = insert(:package)

      insert(:workload_identity,
        package: other_package,
        repository_owner: tp.repository_owner,
        repository_owner_id: tp.repository_owner_id,
        repository_id: tp.repository_id,
        repository: tp.repository,
        workflow: tp.workflow
      )

      first_oidc =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      second_oidc =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, first} =
               WorkloadIdentities.verify_and_mint(first_oidc,
                 repository: "hexpm",
                 package: package.name
               )

      assert {:ok, second} =
               WorkloadIdentities.verify_and_mint(second_oidc,
                 repository: "hexpm",
                 package: other_package.name
               )

      assert first.scopes == ["package:hexpm/#{package.name}"]
      assert second.scopes == ["package:hexpm/#{other_package.name}"]

      assert {:error, :token_replayed} =
               WorkloadIdentities.verify_and_mint(first_oidc,
                 repository: "hexpm",
                 package: other_package.name
               )
    end

    test "rejects a used OIDC token whatever scope it asks for", %{package: package} do
      oidc = WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, _} =
               WorkloadIdentities.verify_and_mint(oidc,
                 repository: "hexpm",
                 package: package.name
               )

      assert {:error, :token_replayed} =
               WorkloadIdentities.verify_and_mint(oidc, repository: "missing")

      assert {:error, :token_replayed} =
               WorkloadIdentities.verify_and_mint(oidc, repository: "hexpm", package: "missing")
    end

    test "rejects replayed OIDC jti", %{package: package} do
      claims = WorkloadIdentityHelpers.github_claims() |> Map.put("jti", "fixed-jti-1")
      token = WorkloadIdentityHelpers.sign_oidc_claims(claims)

      assert {:ok, _} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )

      assert {:error, :token_replayed} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects audience mismatch", %{package: package} do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(
          Map.put(WorkloadIdentityHelpers.github_claims(), "aud", "wrong")
        )

      assert {:error, :audience_mismatch} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects a token minted for another deployment's audience", %{package: package} do
      token = WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      previous = Application.get_env(:hexpm, :workload_identity)
      Application.put_env(:hexpm, :workload_identity, audience: "hexpm-staging")
      on_exit(fn -> Application.put_env(:hexpm, :workload_identity, previous) end)

      assert {:error, :audience_mismatch} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )

      staging_token =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, _} =
               WorkloadIdentities.verify_and_mint(staging_token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "counts a failed JWKS fetch under a reason the metric can export", %{
      package: package
    } do
      stub(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
        {:error, %RuntimeError{message: "connection refused"}}
      end)

      Hexpm.WorkloadIdentities.OIDC.clear_cache()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:hexpm, :workload_identity, :mint, :failure]
        ])

      on_exit(fn -> :telemetry.detach(ref) end)

      token = WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:error, %RuntimeError{}} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )

      assert_received {[:hexpm, :workload_identity, :mint, :failure], ^ref, %{count: 1},
                       %{reason: :request_failed}}
    end

    test "rejects issuer not in allowlist", %{package: package} do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(
          Map.put(WorkloadIdentityHelpers.github_claims(), "iss", "https://evil.example.com")
        )

      assert {:error, :issuer_not_allowed} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects non-string issuer", %{package: package} do
      # Build a token with a non-string iss claim via JOSE.
      claims =
        Map.merge(WorkloadIdentityHelpers.github_claims(), %{
          "iss" => 123,
          "aud" => "hexpm",
          "iat" => System.system_time(:second),
          "nbf" => System.system_time(:second) - 30,
          "exp" => System.system_time(:second) + 600,
          "jti" => "bad-iss"
        })

      {_, signed} =
        JOSE.JWT.sign(WorkloadIdentityHelpers.rsa_jwk(), %{"alg" => "RS256"}, claims)

      {_, token} = JOSE.JWS.compact(signed)

      assert {:error, :issuer_missing} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects mismatched repository_owner_id", %{package: package} do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(
          WorkloadIdentityHelpers.github_claims(repository_owner_id: "99999")
        )

      assert {:error, :no_matching_identity} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects wrong workflow", %{package: package} do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(
          WorkloadIdentityHelpers.github_claims(workflow: "other.yml")
        )

      assert {:error, :no_matching_identity} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "returns :disabled when feature flag is off", %{package: package} do
      previous = Application.get_env(:hexpm, :features)
      Application.put_env(:hexpm, :features, workload_identity: false)
      on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

      token =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:error, :disabled} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end
  end

  describe "verify_and_mint/2 repository id pinning" do
    test "rejects a repository recreated under the same name", %{package: package} do
      recreated =
        WorkloadIdentityHelpers.sign_oidc_claims(
          WorkloadIdentityHelpers.github_claims(repository_id: "99999")
        )

      assert {:error, :no_matching_identity} =
               WorkloadIdentities.verify_and_mint(recreated,
                 repository: "hexpm",
                 package: package.name
               )
    end

    test "rejects a token carrying no repository id", %{package: package} do
      token =
        WorkloadIdentityHelpers.sign_oidc_claims(
          Map.delete(WorkloadIdentityHelpers.github_claims(), "repository_id")
        )

      assert {:error, :no_matching_identity} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end
  end

  describe "create/3" do
    test "resolves immutable ids and stores workload identity", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "Acme",
                   "repository" => "Widget",
                   "workflow" => "Release.yml"
                 },
                 audit: audit_data(user)
               )

      assert identity.repository == "acme/widget"
      assert identity.repository_owner == "acme"
      assert identity.workflow == "Release.yml"
      assert identity.repository_owner_id == "42"
      assert identity.repository_id == "99"
    end

    test "refuses a user who stopped being a full owner during the GitHub lookup", %{
      user: user
    } do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      transfer = fn ->
        Repo.delete_all(
          from(o in Hexpm.Repository.PackageOwner, where: o.package_id == ^package.id)
        )

        insert(:package_owner, package: package, user: insert(:user), level: "full")
        :ok
      end

      assert {:error, :not_owner} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "workflow" => "release.yml"
                 },
                 audit: audit_data(user),
                 before_lookup: transfer
               )

      assert WorkloadIdentities.list(package) == []
    end

    test "authenticates GitHub lookups with the OAuth app credentials", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      previous = Application.get_env(:ueberauth, Ueberauth.Strategy.Github.OAuth)

      Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth,
        client_id: "client-id",
        client_secret: "client-secret"
      )

      on_exit(fn ->
        Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, previous)
      end)

      authorization = "Basic " <> Base.encode64("client-id:client-secret")

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", headers, _ ->
        assert {"authorization", ^authorization} = List.keyfind(headers, "authorization", 0)
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      assert {:ok, _identity} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "workflow" => "release.yml"
                 },
                 audit: audit_data(user)
               )
    end

    test "looks up GitHub without credentials when no OAuth app is configured", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      previous = Application.get_env(:ueberauth, Ueberauth.Strategy.Github.OAuth)
      Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, [])

      on_exit(fn ->
        Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, previous)
      end)

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", headers, _ ->
        refute List.keyfind(headers, "authorization", 0)
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      assert {:ok, _identity} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "workflow" => "release.yml"
                 },
                 audit: audit_data(user)
               )
    end

    test "emails every package owner", %{user: user} do
      other_owner = insert(:user)

      package =
        insert(:package,
          package_owners: [
            build(:package_owner, user: user, level: "full"),
            build(:package_owner, user: other_owner, level: "maintainer")
          ]
        )

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "workflow" => "release.yml",
                   "environment" => "production"
                 },
                 audit: audit_data(user)
               )

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity added to package #{package.name}"
        assert email.text_body =~ "#{user.username} added a workload identity"
        assert email.text_body =~ "acme/widget"
        assert email.text_body =~ "Environment: production"

        assert Enum.sort(Enum.map(email.to, &elem(&1, 1))) ==
                 Enum.sort([
                   Hexpm.Accounts.User.email(user, :primary),
                   Hexpm.Accounts.User.email(other_owner, :primary)
                 ])
      end)

      assert identity.package_id == package.id
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

      expect(Hexpm.HTTP.Mock, :get, 2, fn
        "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      for package <- packages do
        assert {:ok, identity} =
                 WorkloadIdentities.create(package, params, audit: audit_data(user))

        assert identity.package_id == package.id
        assert identity.repository == "acme/widget"
      end
    end

    test "rejects an environment that differs only by casing", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      expect(Hexpm.HTTP.Mock, :get, 2, fn
        "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repository" => "widget",
        "workflow" => "release.yml"
      }

      assert {:ok, _identity} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "environment", "Production"),
                 audit: audit_data(user)
               )

      assert {:error, changeset} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "environment", "production"),
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:repository]
    end
  end

  describe "delete/2" do
    test "emails every package owner", %{user: user, workload_identity: workload_identity} do
      assert {:ok, _} = WorkloadIdentities.delete(workload_identity, audit: audit_data(user))

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity removed from package"
        assert email.text_body =~ "#{user.username} removed a workload identity"
        assert email.text_body =~ "Workflow: release.yml"
        refute email.text_body =~ "Environment:"
        assert email.to == [{user.username, Hexpm.Accounts.User.email(user, :primary)}]
      end)
    end

    test "revokes the workload identity's tokens and keeps their rows", %{
      user: user,
      package: package,
      workload_identity: workload_identity
    } do
      oidc = WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, token} =
               WorkloadIdentities.verify_and_mint(oidc,
                 repository: "hexpm",
                 package: package.name
               )

      assert {:ok, _} = WorkloadIdentities.delete(workload_identity, audit: audit_data(user))

      reloaded = Repo.get!(Hexpm.OAuth.Token, token.id)
      assert reloaded.revoked_at
      assert reloaded.workload_identity_id == workload_identity.id

      assert {:error, :invalid} =
               Hexpm.Accounts.Auth.oauth_token_auth(token.access_token, %{})
    end

    test "an exchanged OIDC token stays used after its workload identity is removed", %{
      user: user,
      package: package,
      workload_identity: tp
    } do
      other_package = insert(:package)

      insert(:workload_identity,
        package: other_package,
        repository_owner: tp.repository_owner,
        repository_owner_id: tp.repository_owner_id,
        repository_id: tp.repository_id,
        repository: tp.repository,
        workflow: tp.workflow
      )

      oidc = WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:ok, _} =
               WorkloadIdentities.verify_and_mint(oidc,
                 repository: "hexpm",
                 package: package.name
               )

      assert {:ok, _} = WorkloadIdentities.delete(tp, audit: audit_data(user))

      assert {:error, :token_replayed} =
               WorkloadIdentities.verify_and_mint(oidc,
                 repository: "hexpm",
                 package: other_package.name
               )
    end
  end

  describe "verify_and_mint/2 event filter" do
    test "rejects a token from a workflow_run workflow", %{package: package} do
      token =
        WorkloadIdentityHelpers.github_claims()
        |> Map.put("event_name", "workflow_run")
        |> WorkloadIdentityHelpers.sign_oidc_claims()

      assert {:error, :event_not_allowed} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end
  end

  describe "verify_and_mint/2 with organization workload identities" do
    setup do
      repository = insert(:repository)
      %{repository: repository, organization: repository.organization}
    end

    defp mint(opts, claims \\ []) do
      claims
      |> WorkloadIdentityHelpers.github_claims()
      |> WorkloadIdentityHelpers.sign_oidc_claims()
      |> WorkloadIdentities.verify_and_mint(opts)
    end

    test "mints a repository token for a read workload identity with no workflow", %{
      repository: repository,
      organization: organization
    } do
      tp =
        insert(:organization_workload_identity,
          organization: organization,
          repository: "acme/widget"
        )

      assert {:ok, token} = mint([repository: repository.name], workflow: "test.yml")
      assert token.scopes == ["repository:#{repository.name}"]
      assert token.workload_identity_id == tp.id

      {:ok, claims} = Joken.peek_claims(token.access_token)
      assert claims["sub"] == "workload_identity:#{tp.id}"
      assert claims["scope"] == "repository:#{repository.name}"
    end

    test "mints a repository token for a write workload identity", %{
      repository: repository,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml"
      )

      assert {:ok, token} = mint(repository: repository.name)
      assert token.scopes == ["repository:#{repository.name}"]

      assert {:error, :no_matching_identity} =
               mint([repository: repository.name], workflow: "test.yml")
    end

    test "matches the environment of a read workload identity", %{
      repository: repository,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        repository: "acme/widget",
        environment: "CI"
      )

      assert {:error, :no_matching_identity} = mint(repository: repository.name)
      assert {:ok, _token} = mint([repository: repository.name], environment: "ci")
    end

    test "mints a repository token for every repository of the owner", %{
      repository: repository,
      organization: organization
    } do
      tp =
        insert(:organization_workload_identity,
          organization: organization,
          repository: "",
          repository_id: ""
        )

      assert {:ok, token} =
               mint([repository: repository.name],
                 repository: "acme/gadget",
                 repository_id: "70001",
                 workflow: "ci.yml"
               )

      assert token.workload_identity_id == tp.id

      assert {:error, :no_matching_identity} =
               mint([repository: repository.name],
                 repository_owner: "other",
                 repository_owner_id: "999"
               )

      package = insert(:package, repository_id: repository.id)

      assert {:error, :no_matching_identity} =
               mint(repository: repository.name, package: package.name)
    end

    test "refuses a repository token from a package workload identity", %{repository: repository} do
      package = insert(:package, repository_id: repository.id)

      insert(:workload_identity,
        package: package,
        repository: "acme/widget",
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} = mint(repository: repository.name)
    end

    test "refuses a repository token for the public repository" do
      insert(:organization_workload_identity,
        organization: Repo.get!(Hexpm.Accounts.Organization, 1),
        repository: "acme/widget"
      )

      assert {:error, :no_matching_identity} = mint(repository: "hexpm")
    end

    test "refuses an unknown repository" do
      assert {:error, :repository_not_found} = mint(repository: "missing")
    end

    test "checks billing only after a match", %{
      repository: repository,
      organization: organization
    } do
      organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Repo.update!()

      assert {:error, :no_matching_identity} = mint(repository: repository.name)

      insert(:organization_workload_identity,
        organization: organization,
        repository: "acme/widget"
      )

      assert {:error, :billing_inactive} = mint(repository: repository.name)
    end

    test "mints a package token from a write workload identity for an existing package", %{
      repository: repository,
      organization: organization
    } do
      package = insert(:package, repository_id: repository.id)

      tp =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repository: "acme/widget",
          workflow: "release.yml"
        )

      assert {:ok, token} = mint(repository: repository.name, package: package.name)
      assert token.scopes == ["package:#{repository.name}/#{package.name}"]
      assert token.workload_identity_id == tp.id
    end

    test "mints a package token for a package that doesn't exist yet", %{
      repository: repository,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml",
        packages: ["new_package"]
      )

      assert {:ok, token} = mint(repository: repository.name, package: "new_package")
      assert token.scopes == ["package:#{repository.name}/new_package"]

      assert {:error, :package_not_found} =
               mint(repository: repository.name, package: "other_package")
    end

    test "refuses a name no package can be created with", %{
      repository: repository,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml"
      )

      for name <- ["new_package\n", "New_package", "new-package", "1package", "a", "elixir"] do
        assert {:error, :invalid_package_name} =
                 mint(repository: repository.name, package: name)
      end

      assert {:ok, _token} = mint(repository: repository.name, package: "new_package")
    end

    test "mints for an existing package whose name predates the name rules", %{
      repository: repository,
      organization: organization
    } do
      package = insert(:package, repository_id: repository.id, name: "Legacy_Package")

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml"
      )

      assert {:ok, token} = mint(repository: repository.name, package: package.name)
      assert token.scopes == ["package:#{repository.name}/Legacy_Package"]
    end

    test "ignores package workload identities on a private package", %{
      repository: repository,
      organization: organization
    } do
      package = insert(:package, repository_id: repository.id)

      insert(:workload_identity,
        package: package,
        repository: "acme/widget",
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} =
               mint(repository: repository.name, package: package.name)

      organization_identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repository: "acme/widget",
          workflow: "release.yml"
        )

      assert {:ok, token} = mint(repository: repository.name, package: package.name)
      assert token.workload_identity_id == organization_identity.id
    end

    test "refuses a package token from a read workload identity", %{
      repository: repository,
      organization: organization
    } do
      package = insert(:package, repository_id: repository.id)

      insert(:organization_workload_identity,
        organization: organization,
        repository: "acme/widget",
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} =
               mint(repository: repository.name, package: package.name)
    end

    test "never uses organization workload identities for the public repository", %{
      package: package
    } do
      insert(:organization_workload_identity,
        organization: Repo.get!(Hexpm.Accounts.Organization, 1),
        role: "write",
        repository: "acme/other",
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} =
               mint([repository: "hexpm", package: package.name], repository: "acme/other")
    end

    test "refuses a package token when billing is inactive", %{
      repository: repository,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml"
      )

      organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Repo.update!()

      assert {:error, :billing_inactive} =
               mint(repository: repository.name, package: "new_package")
    end
  end

  describe "list_covering/1" do
    test "lists the write workload identities whose package list covers the package" do
      repository = insert(:repository)
      organization = repository.organization
      package = insert(:package, repository_id: repository.id)
      package = %{package | repository: repository}

      all =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "all.yml"
        )

      listed =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "listed.yml",
          packages: [package.name]
        )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        workflow: "other.yml",
        packages: ["other"]
      )

      insert(:organization_workload_identity, organization: organization)
      insert(:organization_workload_identity, role: "write", workflow: "elsewhere.yml")

      assert Enum.map(WorkloadIdentities.list_covering(package), & &1.id) == [all.id, listed.id]
    end

    test "is empty for a public package", %{package: package} do
      package = Repo.preload(package, :repository)
      assert WorkloadIdentities.list_covering(package) == []
    end
  end

  describe "create/3 for an organization" do
    setup do
      admin = insert(:user)
      other_admin = insert(:user)
      member = insert(:user)

      repository =
        insert(:repository,
          organization:
            build(:organization,
              organization_users: [
                build(:organization_user, user: admin, role: "admin"),
                build(:organization_user, user: other_admin, role: "admin"),
                build(:organization_user, user: member, role: "write")
              ]
            )
        )

      %{admin: admin, other_admin: other_admin, organization: repository.organization}
    end

    test "stores the workload identity, audits it and emails every admin", %{
      admin: admin,
      other_admin: other_admin,
      organization: organization
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 organization,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "role" => "write",
                   "workflow" => "release.yml",
                   "packages" => "widget"
                 },
                 audit: audit_data(admin)
               )

      assert identity.organization_id == organization.id
      assert identity.package_id == nil
      assert identity.role == "write"
      assert identity.packages == ["widget"]
      assert identity.repository_id == "99"

      log = Repo.get_by!(AuditLog, action: "organization.workload_identity.add")
      assert log.organization_id == organization.id
      assert log.user_id == admin.id
      assert log.params["role"] == "write"
      assert log.params["packages"] == ["widget"]
      assert log.params["organization"]["name"] == organization.name

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity added to organization #{organization.name}"
        assert email.text_body =~ "#{admin.username} added a workload identity"
        assert email.text_body =~ "Role: write"
        assert email.text_body =~ "Packages: widget"
        assert email.text_body =~ "publish and create the packages listed above"

        assert Enum.sort(Enum.map(email.to, &elem(&1, 1))) ==
                 Enum.sort([
                   Hexpm.Accounts.User.email(admin, :primary),
                   Hexpm.Accounts.User.email(other_admin, :primary)
                 ])
      end)
    end

    test "stores a read workload identity with no workflow", %{
      admin: admin,
      organization: organization
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 organization,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "role" => "read",
                   "workflow" => ""
                 },
                 audit: audit_data(admin)
               )

      assert identity.workflow == ""

      assert_email_sent(fn email ->
        refute email.text_body =~ "Packages:"
        assert email.text_body =~ "Workflow: any"
        assert email.text_body =~ "fetch every package in the #{organization.name} repository"
      end)
    end

    test "stores a read workload identity for every repository of the owner", %{
      admin: admin,
      organization: organization
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 42}}
      end)

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 organization,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "",
                   "role" => "read"
                 },
                 audit: audit_data(admin)
               )

      assert identity.repository == ""
      assert identity.repository_id == ""
      assert identity.repository_owner_id == "42"

      assert_email_sent(fn email ->
        assert email.text_body =~ "GitHub repository: any repository owned by acme"
      end)
    end

    test "rejects the same configuration twice", %{admin: admin, organization: organization} do
      expect(Hexpm.HTTP.Mock, :get, 2, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repository" => "widget",
        "role" => "read",
        "workflow" => "ci.yml"
      }

      assert {:ok, _} = WorkloadIdentities.create(organization, params, audit: audit_data(admin))

      assert {:error, changeset} =
               WorkloadIdentities.create(
                 organization,
                 Map.put(params, "role", "write"),
                 audit: audit_data(admin)
               )

      assert "workload identity already configured for this organization" in List.wrap(
               errors_on(changeset).repository
             )
    end

    test "refuses a package workload identity on a private package", %{
      admin: admin,
      organization: organization
    } do
      repository = Repo.get_by!(Hexpm.Repository.Repository, organization_id: organization.id)
      package = insert(:package, repository_id: repository.id)

      assert {:error, :not_allowed} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "workflow" => "release.yml"
                 },
                 audit: audit_data(admin)
               )
    end

    test "refuses the hexpm organization", %{admin: admin} do
      organization = Repo.get!(Hexpm.Accounts.Organization, 1)

      assert {:error, :not_allowed} =
               WorkloadIdentities.create(
                 organization,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repository" => "widget",
                   "role" => "read"
                 },
                 audit: audit_data(admin)
               )
    end
  end

  describe "delete/2 for an organization" do
    test "audits the removal and emails every admin" do
      admin = insert(:user)

      organization =
        insert(:organization,
          organization_users: [build(:organization_user, user: admin, role: "admin")]
        )

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          repository: "acme/widget"
        )

      assert {:ok, _} = WorkloadIdentities.delete(identity, audit: audit_data(admin))
      refute Repo.get(Hexpm.WorkloadIdentities.WorkloadIdentity, identity.id)

      log = Repo.get_by!(AuditLog, action: "organization.workload_identity.remove")
      assert log.organization_id == organization.id
      assert log.params["repository"] == "acme/widget"

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity removed from organization #{organization.name}"
        assert email.text_body =~ "#{admin.username} removed a workload identity"
        assert Enum.map(email.to, &elem(&1, 1)) == [Hexpm.Accounts.User.email(admin, :primary)]
      end)
    end
  end
end

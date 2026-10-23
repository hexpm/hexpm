defmodule Hexpm.WorkloadIdentitiesTest do
  use Hexpm.DataCase, async: false
  import Mox
  import Swoosh.TestAssertions

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.WorkloadIdentities
  alias Hexpm.WorkloadIdentities.TrustedRepository
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
        repositories: [trusted("acme/widget")],
        workflow: "release.yml"
      )

    %{user: user, package: package, workload_identity: workload_identity}
  end

  defp trusted(name, id \\ "67890"), do: %TrustedRepository{name: name, id: id}

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

    test "matches no token from a public repository without an environment", %{
      package: package,
      workload_identity: workload_identity
    } do
      mint = fn claims ->
        claims
        |> WorkloadIdentityHelpers.github_claims()
        |> WorkloadIdentityHelpers.sign_oidc_claims()
        |> WorkloadIdentities.verify_and_mint(
          repository: "hexpm",
          package: package.name,
          audit: audit_data(insert(:user))
        )
      end

      assert {:error, :no_matching_identity} =
               mint.(repository_visibility: "public", environment: "release")

      workload_identity
      |> Ecto.Changeset.change(environment: "release")
      |> Repo.update!()

      assert {:ok, _token} = mint.(repository_visibility: "public", environment: "release")
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
        repositories: tp.repositories,
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
      put_feature_flag(:workload_identity, mode: :off)

      token =
        WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

      assert {:error, :disabled} =
               WorkloadIdentities.verify_and_mint(token,
                 repository: "hexpm",
                 package: package.name
               )
    end
  end

  describe "beta" do
    setup do
      put_feature_flag(:workload_identity, mode: :beta, beta_users: [], beta_organizations: [])
    end

    test "verify_and_mint/2 mints for a package with an owner on the user list", %{
      user: user,
      package: package
    } do
      put_feature_flag(:workload_identity, beta_users: ["someone-else"])
      assert {:error, :disabled} = mint(repository: "hexpm", package: package.name)

      put_feature_flag(:workload_identity, beta_users: [user.username])
      assert {:ok, _token} = mint(repository: "hexpm", package: package.name)
    end

    test "verify_and_mint/2 mints for an organization on the organization list" do
      repository = insert(:repository)

      insert(:organization_workload_identity,
        organization: repository.organization,
        repositories: [trusted("acme/widget")]
      )

      put_feature_flag(:workload_identity, beta_organizations: ["someone-else"])
      assert {:error, :disabled} = mint(repository: repository.name)

      put_feature_flag(:workload_identity, beta_organizations: [repository.organization.name])
      assert {:ok, _token} = mint(repository: repository.name)
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
                   "repositories" => "Widget",
                   "workflow" => "Release.yml"
                 },
                 audit: audit_data(user)
               )

      assert identity.repositories == [trusted("acme/widget", "99")]
      assert identity.repository_owner == "acme"
      assert identity.workflow == "Release.yml"
      assert identity.repository_owner_id == "42"
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

      transfer = fn _calls ->
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
                   "repositories" => "widget",
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
                   "repositories" => "widget",
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
                   "repositories" => "widget",
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
                   "repositories" => "widget",
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
        "repositories" => "widget",
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
        assert identity.repositories == [trusted("acme/widget", "99")]
      end
    end

    test "rejects an environment that differs only by casing", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      expect(Hexpm.HTTP.Mock, :get, fn
        "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repositories" => "widget",
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

      assert errors_on(changeset)[:repositories] ==
               "already have a workload identity with this workflow and environment"
    end

    test "rejects the same repositories in another order", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      insert(:workload_identity,
        package: package,
        repositories: [trusted("acme/widget", "1"), trusted("acme/gadget", "2")],
        workflow: "release.yml"
      )

      assert {:error, changeset} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repositories" => "gadget\nwidget",
                   "workflow" => "release.yml"
                 },
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:repositories]
    end

    test "adds a workload identity with an overlapping set of repositories", %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      insert(:workload_identity,
        package: package,
        repositories: [trusted("acme/widget", "1"), trusted("acme/gadget", "2")],
        workflow: "release.yml"
      )

      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 1, "owner" => %{"id" => 12345}}}
      end)

      assert {:ok, _identity} =
               WorkloadIdentities.create(
                 package,
                 %{
                   "provider" => "github",
                   "repository_owner" => "acme",
                   "repositories" => "widget",
                   "workflow" => "release.yml"
                 },
                 audit: audit_data(user)
               )
    end
  end

  describe "create/3 from a public repository" do
    setup %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}, "visibility" => "public"}}
      end)

      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repositories" => "widget",
        "workflow" => "release.yml"
      }

      %{package: package, params: params}
    end

    test "requires an environment", %{user: user, package: package, params: params} do
      assert {:error, changeset} =
               WorkloadIdentities.create(package, params, audit: audit_data(user))

      assert errors_on(changeset)[:environment] == "is required because acme/widget is public"
      assert WorkloadIdentities.list(package) == []

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "environment", "release"),
                 audit: audit_data(user)
               )

      assert identity.environment == "release"
    end
  end

  describe "create/3 with several repositories" do
    setup %{user: user} do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: user, level: "full")]
        )

      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "workflow" => "release.yml"
      }

      %{package: package, params: params}
    end

    test "reads each repository's ID from GitHub", %{user: user, package: package, params: params} do
      stub_github(%{"widget" => {99, "private"}, "gadget" => {100, "private"}})

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "repositories", "widget\nGadget"),
                 audit: audit_data(user)
               )

      assert identity.repositories == [
               trusted("acme/widget", "99"),
               trusted("acme/gadget", "100")
             ]

      assert identity.repository_owner_id == "12345"
    end

    test "uses the ID GitHub reports over a typed one, and a typed one for a repository Hex can't see",
         %{user: user, package: package, params: params} do
      stub_github(%{"widget" => {99, "private"}})

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "repositories", "widget 11111\ngadget 70001"),
                 audit: audit_data(user)
               )

      assert identity.repositories == [
               trusted("acme/widget", "99"),
               trusted("acme/gadget", "70001")
             ]
    end

    test "names the repository Hex can't see without a typed ID", %{
      user: user,
      package: package,
      params: params
    } do
      stub_github(%{"widget" => {99, "private"}})

      assert {:error, changeset} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "repositories", "widget, gadget"),
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:repositories] ==
               "acme/gadget needs its repository ID after the name, because Hex can't see it on GitHub"

      assert WorkloadIdentities.list(package) == []
    end

    test "reads the owner's ID from its profile when Hex sees none of the repositories", %{
      user: user,
      package: package,
      params: params
    } do
      stub_github(%{})

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "repositories", "widget 70001"),
                 audit: audit_data(user)
               )

      assert identity.repository_owner_id == "12345"
      assert identity.repositories == [trusted("acme/widget", "70001")]
    end

    test "requires an environment and names the public repositories", %{
      user: user,
      package: package,
      params: params
    } do
      stub_github(%{
        "widget" => {99, "public"},
        "gadget" => {100, "private"},
        "gizmo" => {101, "public"}
      })

      params = Map.put(params, "repositories", "widget\ngadget\ngizmo")

      assert {:error, changeset} =
               WorkloadIdentities.create(package, params, audit: audit_data(user))

      assert errors_on(changeset)[:environment] ==
               "is required because acme/widget, acme/gizmo are public"

      assert {:ok, _identity} =
               WorkloadIdentities.create(package, Map.put(params, "environment", "release"),
                 audit: audit_data(user)
               )
    end

    test "refuses repositories GitHub reports under different owners", %{
      user: user,
      package: package,
      params: params
    } do
      stub(Hexpm.HTTP.Mock, :get, fn
        "https://api.github.com/repos/acme/widget", _, _ ->
          {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 12345}}}

        "https://api.github.com/repos/acme/gadget", _, _ ->
          {:ok, 200, [], %{"id" => 100, "owner" => %{"id" => 999}}}
      end)

      assert {:error, :repository_not_found} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "repositories", "widget\ngadget"),
                 audit: audit_data(user)
               )
    end

    test "matches a token from any of its repositories by name and ID", %{
      user: user,
      package: package,
      params: params
    } do
      stub_github(%{"widget" => {99, "private"}, "gadget" => {100, "private"}})

      assert {:ok, _identity} =
               WorkloadIdentities.create(
                 package,
                 Map.put(params, "repositories", "widget\ngadget"),
                 audit: audit_data(user)
               )

      WorkloadIdentityHelpers.stub_oidc_discovery()
      opts = [repository: "hexpm", package: package.name]

      assert {:ok, _token} = mint(opts, repository: "acme/gadget", repository_id: "100")
      assert {:ok, _token} = mint(opts, repository: "acme/widget", repository_id: "99")

      assert {:error, :no_matching_identity} =
               mint(opts, repository: "acme/gadget", repository_id: "99")

      assert {:error, :no_matching_identity} =
               mint(opts, repository: "acme/gizmo", repository_id: "100")
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
        repositories: tp.repositories,
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

    test "returns not found for a workload identity removed in the meantime", %{
      user: user,
      workload_identity: workload_identity
    } do
      assert {:ok, _} = WorkloadIdentities.delete(workload_identity, audit: audit_data(user))

      assert {:error, :not_found} =
               WorkloadIdentities.delete(workload_identity, audit: audit_data(user))
    end

    test "audits and emails the workload identity as it is when it's removed", %{
      user: user,
      workload_identity: workload_identity
    } do
      workload_identity
      |> Ecto.Changeset.change(workflow: "other.yml")
      |> Repo.update!()

      assert {:ok, _} = WorkloadIdentities.delete(workload_identity, audit: audit_data(user))

      log = Repo.get_by!(AuditLog, action: "workload_identity.remove")
      assert log.params["workflow"] == "other.yml"

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity removed from package"
        assert email.text_body =~ "Workflow: other.yml"
      end)
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
          repositories: [trusted("acme/widget")]
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
        repositories: [trusted("acme/widget")],
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
        repositories: [trusted("acme/widget")],
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
          repositories: []
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
        repositories: [trusted("acme/widget")],
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} = mint(repository: repository.name)
    end

    test "refuses a repository token for the public repository" do
      insert(:organization_workload_identity,
        organization: Repo.get!(Hexpm.Accounts.Organization, 1),
        repositories: [trusted("acme/widget")]
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
        repositories: [trusted("acme/widget")]
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
          repositories: [trusted("acme/widget")],
          workflow: "release.yml"
        )

      assert {:ok, token} = mint(repository: repository.name, package: package.name)
      assert token.scopes == ["package:#{repository.name}/#{package.name}"]
      assert token.workload_identity_id == tp.id
    end

    test "a write workload identity matches no token from a public repository without an environment",
         %{repository: repository, organization: organization} do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: [trusted("acme/widget")],
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} =
               mint([repository: repository.name, package: "widget"],
                 repository_visibility: "public"
               )

      assert {:error, :no_matching_identity} =
               mint([repository: repository.name], repository_visibility: "public")

      assert {:ok, _token} = mint(repository: repository.name, package: "widget")
    end

    test "a read workload identity matches a token from a public repository without an environment",
         %{repository: repository, organization: organization} do
      insert(:organization_workload_identity,
        organization: organization,
        repositories: [trusted("acme/widget")]
      )

      assert {:ok, _token} = mint([repository: repository.name], repository_visibility: "public")
    end

    test "mints a package token for a package that doesn't exist yet", %{
      repository: repository,
      organization: organization
    } do
      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: [trusted("acme/widget")],
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
        repositories: [trusted("acme/widget")],
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
        repositories: [trusted("acme/widget")],
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
        repositories: [trusted("acme/widget")],
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} =
               mint(repository: repository.name, package: package.name)

      organization_identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repositories: [trusted("acme/widget")],
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
        repositories: [trusted("acme/widget")],
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
        repositories: [trusted("acme/other")],
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
        repositories: [trusted("acme/widget")],
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
                   "repositories" => "widget",
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
      assert identity.repositories == [trusted("acme/widget", "99")]

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
        assert email.text_body =~ "Private packages: widget"
        assert email.text_body =~ "publish and create the private packages listed above"

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
                   "repositories" => "widget",
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
                   "repositories" => "",
                   "role" => "read"
                 },
                 audit: audit_data(admin)
               )

      assert identity.repositories == []
      assert identity.repository_owner_id == "42"

      assert_email_sent(fn email ->
        assert email.text_body =~ "GitHub repositories: any repository owned by acme"
      end)
    end

    test "requires an environment on a write workload identity from a public repository", %{
      admin: admin,
      organization: organization
    } do
      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}, "visibility" => "public"}}
      end)

      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repositories" => "widget",
        "workflow" => "release.yml"
      }

      assert {:error, changeset} =
               WorkloadIdentities.create(
                 organization,
                 Map.put(params, "role", "write"),
                 audit: audit_data(admin)
               )

      assert errors_on(changeset)[:environment] == "is required because acme/widget is public"

      assert {:ok, _identity} =
               WorkloadIdentities.create(
                 organization,
                 Map.put(params, "role", "read"),
                 audit: audit_data(admin)
               )
    end

    test "rejects the same configuration twice", %{admin: admin, organization: organization} do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)

      params = %{
        "provider" => "github",
        "repository_owner" => "acme",
        "repositories" => "widget",
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

      assert errors_on(changeset)[:repositories] ==
               "already have a workload identity with this workflow and environment"
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
                   "repositories" => "widget",
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
                   "repositories" => "widget",
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
          repositories: [trusted("acme/widget")]
        )

      assert {:ok, _} = WorkloadIdentities.delete(identity, audit: audit_data(admin))
      refute Repo.get(Hexpm.WorkloadIdentities.WorkloadIdentity, identity.id)

      log = Repo.get_by!(AuditLog, action: "organization.workload_identity.remove")
      assert log.organization_id == organization.id
      assert log.params["repositories"] == [%{"name" => "acme/widget", "id" => "67890"}]

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity removed from organization #{organization.name}"
        assert email.text_body =~ "#{admin.username} removed a workload identity"
        assert Enum.map(email.to, &elem(&1, 1)) == [Hexpm.Accounts.User.email(admin, :primary)]
      end)
    end
  end

  describe "verify_and_mint/2 with public coverage" do
    setup do
      admin = insert(:user)

      organization =
        insert(:organization,
          organization_users: [build(:organization_user, user: admin, role: "admin")]
        )

      owned =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repositories: [trusted("acme/widget")],
          workflow: "release.yml",
          covers_private: false,
          packages: [],
          covers_public: true
        )

      %{admin: admin, organization: organization, owned: owned, identity: identity}
    end

    defp mint_public(name, claims \\ []) do
      claims
      |> WorkloadIdentityHelpers.github_claims()
      |> WorkloadIdentityHelpers.sign_oidc_claims()
      |> WorkloadIdentities.verify_and_mint(repository: "hexpm", package: name)
    end

    test "mints a package token for a public package the organization owns", %{
      organization: organization,
      owned: owned,
      identity: identity
    } do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:hexpm, :workload_identity, :mint, :success]
        ])

      assert {:ok, token} = mint_public(owned.name)
      assert token.scopes == ["package:hexpm/#{owned.name}"]
      assert token.workload_identity_id == identity.id

      organization_id = organization.id

      assert_received {[:hexpm, :workload_identity, :mint, :success], ^ref, %{count: 1},
                       %{organization_id: ^organization_id, package_id: nil}}
    end

    test "refuses an organization that owns the package as a maintainer", %{
      organization: organization
    } do
      package =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "maintainer")]
        )

      assert {:error, :no_matching_identity} = mint_public(package.name)
    end

    test "refuses a public package the organization doesn't own" do
      package = insert(:package, package_owners: [build(:package_owner, user: insert(:user))])

      assert {:error, :no_matching_identity} = mint_public(package.name)
    end

    test "stops matching once the organization is no longer an owner", %{owned: owned} do
      assert {:ok, _token} = mint_public(owned.name)

      Repo.delete_all(
        from(po in Hexpm.Repository.PackageOwner, where: po.package_id == ^owned.id)
      )

      insert(:package_owner, package: owned, user: insert(:user))

      assert {:error, :no_matching_identity} = mint_public(owned.name)
    end

    test "matches a package the public list names and no other", %{
      organization: organization,
      owned: owned,
      identity: identity
    } do
      other_owned =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )

      identity
      |> Ecto.Changeset.change(public_packages: [owned.name])
      |> Repo.update!()

      assert {:ok, _token} = mint_public(owned.name)
      assert {:error, :no_matching_identity} = mint_public(other_owned.name)
    end

    test "a listed name that isn't a package matches nothing", %{identity: identity} do
      identity
      |> Ecto.Changeset.change(public_packages: ["new_package"])
      |> Repo.update!()

      assert {:error, :package_not_found} = mint_public("new_package")
      assert {:error, :package_not_found} = mint_public("other_package")
    end

    test "covering every owned package matches no name that isn't a package" do
      assert {:error, :package_not_found} = mint_public("new_package")
    end

    test "matches the earlier identity when two owning organizations match", %{
      organization: organization,
      owned: owned,
      identity: identity
    } do
      other_organization = insert(:organization)
      insert(:package_owner, package: owned, user: other_organization.user, level: "full")

      insert(:organization_workload_identity,
        organization: other_organization,
        role: "write",
        repositories: [trusted("acme/widget")],
        workflow: "release.yml",
        covers_private: false,
        packages: [],
        covers_public: true
      )

      owners = fn ->
        Repo.all(
          from(po in Hexpm.Repository.PackageOwner,
            where: po.package_id == ^owned.id,
            order_by: po.id
          )
        )
      end

      owners_before = owners.()

      assert {:ok, token} = mint_public(owned.name)
      assert token.workload_identity_id == identity.id
      assert identity.organization_id == organization.id
      assert owners.() == owners_before
    end

    test "skips a matching identity of an organization without the feature flag", %{
      owned: owned,
      identity: identity
    } do
      other_organization = insert(:organization)
      insert(:package_owner, package: owned, user: other_organization.user, level: "full")

      enabled =
        insert(:organization_workload_identity,
          organization: other_organization,
          role: "write",
          repositories: [trusted("acme/widget")],
          workflow: "release.yml",
          covers_private: false,
          packages: [],
          covers_public: true
        )

      assert identity.id < enabled.id

      flags = Application.fetch_env!(:hexpm, :feature_flags)
      on_exit(fn -> Application.put_env(:hexpm, :feature_flags, flags) end)

      Application.put_env(
        :hexpm,
        :feature_flags,
        Keyword.put(flags, :workload_identity,
          mode: :beta,
          beta_organizations: [other_organization.name]
        )
      )

      assert {:ok, token} = mint_public(owned.name)
      assert token.workload_identity_id == enabled.id
    end

    test "a listed name of a package someone else owns doesn't match", %{identity: identity} do
      package = insert(:package, package_owners: [build(:package_owner, user: insert(:user))])

      identity
      |> Ecto.Changeset.change(public_packages: [package.name])
      |> Repo.update!()

      assert {:error, :no_matching_identity} = mint_public(package.name)
    end

    test "matches the package's own workload identity first", %{owned: owned} do
      own =
        insert(:workload_identity,
          package: owned,
          repositories: [trusted("acme/widget")],
          workflow: "release.yml"
        )

      assert {:ok, token} = mint_public(owned.name)
      assert token.workload_identity_id == own.id
    end

    test "doesn't cover the organization's repository without private coverage", %{
      organization: organization
    } do
      repository = insert(:repository, organization: organization, name: organization.name)
      package = insert(:package, repository_id: repository.id)

      assert {:error, :no_matching_identity} =
               WorkloadIdentityHelpers.github_claims()
               |> WorkloadIdentityHelpers.sign_oidc_claims()
               |> WorkloadIdentities.verify_and_mint(
                 repository: repository.name,
                 package: package.name
               )

      assert {:error, :no_matching_identity} =
               WorkloadIdentityHelpers.github_claims()
               |> WorkloadIdentityHelpers.sign_oidc_claims()
               |> WorkloadIdentities.verify_and_mint(repository: repository.name)
    end

    test "a read workload identity covers no public package", %{
      organization: organization,
      owned: owned,
      identity: identity
    } do
      Repo.delete!(identity)

      insert(:organization_workload_identity,
        organization: organization,
        repositories: [trusted("acme/widget")],
        workflow: "release.yml"
      )

      assert {:error, :no_matching_identity} = mint_public(owned.name)
    end

    test "a write workload identity without public coverage covers no public package", %{
      owned: owned,
      identity: identity
    } do
      identity
      |> Ecto.Changeset.change(covers_private: true, packages: nil, covers_public: false)
      |> Repo.update!()

      assert {:error, :no_matching_identity} = mint_public(owned.name)
    end

    test "doesn't need active billing", %{organization: organization, owned: owned} do
      organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Repo.update!()

      assert {:ok, _token} = mint_public(owned.name)
    end

    test "follows the feature flag on the organization", %{
      organization: organization,
      owned: owned
    } do
      flags = Application.fetch_env!(:hexpm, :feature_flags)
      on_exit(fn -> Application.put_env(:hexpm, :feature_flags, flags) end)

      Application.put_env(
        :hexpm,
        :feature_flags,
        Keyword.put(flags, :workload_identity, mode: :beta, beta_organizations: ["other"])
      )

      assert {:error, :disabled} = mint_public(owned.name)

      Application.put_env(
        :hexpm,
        :feature_flags,
        Keyword.put(flags, :workload_identity,
          mode: :beta,
          beta_organizations: [organization.name]
        )
      )

      assert {:ok, _token} = mint_public(owned.name)
    end
  end

  describe "list_covering/1 for a public package" do
    test "lists the write workload identities with public coverage of the owning organizations" do
      organization = insert(:organization)

      package =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )

      all =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "all.yml",
          covers_public: true
        )

      listed =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "listed.yml",
          covers_private: false,
          packages: [],
          covers_public: true,
          public_packages: [package.name]
        )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        workflow: "other.yml",
        covers_public: true,
        public_packages: ["other"]
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        workflow: "private.yml"
      )

      insert(:organization_workload_identity, organization: organization)

      insert(:organization_workload_identity,
        role: "write",
        workflow: "elsewhere.yml",
        covers_public: true
      )

      covering = WorkloadIdentities.list_covering(package)
      assert Enum.map(covering, & &1.id) == [all.id, listed.id]
      assert Enum.all?(covering, &(&1.organization.id == organization.id))

      Repo.delete_all(
        from(po in Hexpm.Repository.PackageOwner, where: po.package_id == ^package.id)
      )

      assert WorkloadIdentities.list_covering(package) == []
    end

    test "leaves out organizations without the feature flag" do
      organization = insert(:organization)

      package =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "all.yml",
          covers_public: true
        )

      flags = Application.fetch_env!(:hexpm, :feature_flags)
      on_exit(fn -> Application.put_env(:hexpm, :feature_flags, flags) end)

      Application.put_env(
        :hexpm,
        :feature_flags,
        Keyword.put(flags, :workload_identity, mode: :beta, beta_organizations: ["other"])
      )

      assert WorkloadIdentities.list_covering(package) == []

      Application.put_env(
        :hexpm,
        :feature_flags,
        Keyword.put(flags, :workload_identity,
          mode: :beta,
          beta_organizations: [organization.name]
        )
      )

      assert Enum.map(WorkloadIdentities.list_covering(package), & &1.id) == [identity.id]
    end
  end

  describe "create/3 with public coverage" do
    setup do
      admin = insert(:user)
      co_owner = insert(:user)
      admin_co_owner = insert(:user)

      organization =
        insert(:organization,
          organization_users: [
            build(:organization_user, user: admin, role: "admin"),
            build(:organization_user, user: admin_co_owner, role: "admin")
          ]
        )

      insert(:repository, organization: organization, name: organization.name)

      owned =
        insert(:package,
          name: "owned_one",
          package_owners: [
            build(:package_owner, user: organization.user, level: "full"),
            build(:package_owner, user: co_owner, level: "maintainer"),
            build(:package_owner, user: admin_co_owner, level: "full")
          ]
        )

      other_owned =
        insert(:package,
          name: "owned_two",
          package_owners: [
            build(:package_owner, user: organization.user, level: "full"),
            build(:package_owner, user: co_owner, level: "full")
          ]
        )

      %{
        admin: admin,
        co_owner: co_owner,
        admin_co_owner: admin_co_owner,
        organization: organization,
        owned: owned,
        other_owned: other_owned
      }
    end

    defp public_params(params) do
      Map.merge(
        %{
          "provider" => "github",
          "repository_owner" => "acme",
          "repositories" => "widget",
          "role" => "write",
          "workflow" => "release.yml",
          "covers_private" => "false",
          "packages" => "",
          "covers_public" => "true",
          "public_packages" => ""
        },
        params
      )
    end

    defp expect_github_lookup do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/widget", _, _ ->
        {:ok, 200, [], %{"id" => 99, "owner" => %{"id" => 42}}}
      end)
    end

    test "stores the coverage, audits it and emails the admins and the other owners once each",
         %{
           admin: admin,
           co_owner: co_owner,
           admin_co_owner: admin_co_owner,
           organization: organization
         } do
      expect_github_lookup()

      assert {:ok, identity} =
               WorkloadIdentities.create(organization, public_params(%{}),
                 audit: audit_data(admin)
               )

      assert identity.covers_private == false
      assert identity.packages == []
      assert identity.covers_public == true
      assert identity.public_packages == nil

      log = Repo.get_by!(AuditLog, action: "organization.workload_identity.add")
      assert log.params["covers_private"] == false
      assert log.params["packages"] == []
      assert log.params["covers_public"] == true
      assert log.params["public_packages"] == nil

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity added to organization #{organization.name}"
        refute email.text_body =~ "Private packages"
        assert email.text_body =~ "Public packages: all packages #{organization.name} owns"
        assert email.text_body =~ "publish every public package #{organization.name} owns"
        refute email.text_body =~ "fetch"

        assert Enum.sort(Enum.map(email.to, &elem(&1, 1))) ==
                 Enum.sort([
                   Hexpm.Accounts.User.email(admin, :primary),
                   Hexpm.Accounts.User.email(admin_co_owner, :primary)
                 ])
      end)

      co_owner_email = Hexpm.Accounts.User.email(co_owner, :primary)

      assert_email_sent(fn email ->
        assert Enum.map(email.to, &elem(&1, 1)) == [co_owner_email]
        assert email.subject =~ "Workload identity of organization #{organization.name}"
        assert email.subject =~ "can publish owned_one, owned_two"
        assert email.text_body =~ "#{admin.username} added a workload identity"
        assert email.text_body =~ "owned_one\nowned_two"
        assert email.text_body =~ "GitHub repository: acme/widget"
      end)

      refute_email_sent()
    end

    test "names only each owner's own packages to the owners outside the organization", %{
      admin: admin,
      co_owner: co_owner,
      organization: organization,
      owned: owned,
      other_owned: other_owned
    } do
      expect_github_lookup()
      lone_owner = insert(:user)
      insert(:package_owner, package: owned, user: lone_owner)

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 organization,
                 public_params(%{
                   "covers_private" => "true",
                   "packages" => "private_one",
                   "public_packages" => "#{owned.name}, #{other_owned.name}"
                 }),
                 audit: audit_data(admin)
               )

      assert identity.packages == ["private_one"]
      assert identity.public_packages == [owned.name, other_owned.name]

      assert_email_sent(fn email ->
        assert email.text_body =~ "Private packages: private_one"
        assert email.text_body =~ "Public packages: #{owned.name}, #{other_owned.name}"
      end)

      assert_email_sent(fn email ->
        refute email.text_body =~ "private_one"
        assert Enum.map(email.to, &elem(&1, 1)) == [Hexpm.Accounts.User.email(co_owner, :primary)]
        assert email.text_body =~ "Public packages: #{owned.name}, #{other_owned.name}"
      end)

      assert_email_sent(fn email ->
        refute email.text_body =~ other_owned.name
        refute email.text_body =~ "private_one"

        assert Enum.map(email.to, &elem(&1, 1)) == [
                 Hexpm.Accounts.User.email(lone_owner, :primary)
               ]

        assert email.subject =~ "can publish #{owned.name}"
        assert email.text_body =~ "Public packages: #{owned.name}"
      end)

      refute_email_sent()
    end

    test "refuses listed names that aren't public packages the organization owns before asking GitHub",
         %{admin: admin, organization: organization, owned: owned} do
      someone_elses = insert(:package, package_owners: [build(:package_owner, user: admin)])

      assert {:error, changeset} =
               WorkloadIdentities.create(
                 organization,
                 public_params(%{
                   "public_packages" => "#{owned.name} #{someone_elses.name} new_package"
                 }),
                 audit: audit_data(admin)
               )

      assert errors_on(changeset)[:public_packages] ==
               "must be public packages the organization owns, " <>
                 "not " <> Enum.join(Enum.sort([someone_elses.name, "new_package"]), ", ")

      assert WorkloadIdentities.list(organization) == []
    end

    test "refuses a public package the organization only maintains", %{
      admin: admin,
      organization: organization
    } do
      maintained =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "maintainer")]
        )

      assert {:error, changeset} =
               WorkloadIdentities.create(
                 organization,
                 public_params(%{"public_packages" => maintained.name}),
                 audit: audit_data(admin)
               )

      assert errors_on(changeset)[:public_packages] ==
               "must be public packages the organization owns, not #{maintained.name}"

      assert WorkloadIdentities.list(organization) == []
    end

    test "lists owned public packages whose names a new package can't have", %{
      admin: admin,
      organization: organization
    } do
      expect_github_lookup()

      for name <- ["Legacy_Package", "stats"] do
        insert(:package,
          name: name,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )
      end

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 organization,
                 public_params(%{"public_packages" => "stats Legacy_Package"}),
                 audit: audit_data(admin)
               )

      assert identity.public_packages == ["Legacy_Package", "stats"]
    end

    test "adds public packages without active billing, and refuses private packages and the read role",
         %{admin: admin, organization: organization} do
      organization =
        organization
        |> Ecto.Changeset.change(billing_active: false, trial_end: nil)
        |> Repo.update!()

      for {params, field, message} <- [
            {%{"covers_private" => "true"}, :covers_private,
             "private packages need an active billing subscription"},
            {%{"role" => "read"}, :role, "needs an active billing subscription"}
          ] do
        assert {:error, changeset} =
                 WorkloadIdentities.create(organization, public_params(params),
                   audit: audit_data(admin)
                 )

        assert errors_on(changeset)[field] == message
      end

      expect_github_lookup()

      assert {:ok, identity} =
               WorkloadIdentities.create(organization, public_params(%{}),
                 audit: audit_data(admin)
               )

      assert identity.covers_private == false
      assert identity.covers_public == true
    end

    test "requires private packages, public packages or both", %{
      admin: admin,
      organization: organization
    } do
      assert {:error, changeset} =
               WorkloadIdentities.create(
                 organization,
                 public_params(%{"covers_public" => "false"}),
                 audit: audit_data(admin)
               )

      assert errors_on(changeset)[:covers_private] ==
               "select private packages, public packages or both"
    end

    test "a read workload identity covers the repository and no public package", %{
      admin: admin,
      organization: organization
    } do
      expect_github_lookup()

      assert {:ok, identity} =
               WorkloadIdentities.create(
                 organization,
                 public_params(%{"role" => "read", "public_packages" => "owned_one"}),
                 audit: audit_data(admin)
               )

      assert identity.covers_private == true
      assert identity.packages == nil
      assert identity.covers_public == false
      assert identity.public_packages == nil

      assert_email_sent(fn email ->
        refute email.text_body =~ "Public packages"
        assert email.text_body =~ "fetch every package in the #{organization.name} repository"
      end)

      refute_email_sent()
    end
  end

  describe "delete/2 with public coverage" do
    test "emails the admins and the other owners of the covered packages" do
      admin = insert(:user)
      co_owner = insert(:user)

      organization =
        insert(:organization,
          organization_users: [build(:organization_user, user: admin, role: "admin")]
        )

      package =
        insert(:package,
          package_owners: [
            build(:package_owner, user: organization.user, level: "full"),
            build(:package_owner, user: co_owner, level: "full")
          ]
        )

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repositories: [trusted("acme/widget")],
          workflow: "release.yml",
          covers_public: true
        )

      assert {:ok, _} = WorkloadIdentities.delete(identity, audit: audit_data(admin))

      log = Repo.get_by!(AuditLog, action: "organization.workload_identity.remove")
      assert log.params["covers_public"] == true

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity removed from organization #{organization.name}"
      end)

      assert_email_sent(fn email ->
        assert Enum.map(email.to, &elem(&1, 1)) == [Hexpm.Accounts.User.email(co_owner, :primary)]
        assert email.subject =~ "can no longer publish #{package.name}"
        assert email.text_body =~ "#{admin.username} removed a workload identity"
      end)

      refute_email_sent()
    end
  end

  defp stub_github(repositories) do
    stub(Hexpm.HTTP.Mock, :get, fn
      "https://api.github.com/users/acme", _, _ ->
        {:ok, 200, [], %{"id" => 12345}}

      "https://api.github.com/repos/acme/" <> name, _, _ ->
        case Map.fetch(repositories, name) do
          {:ok, {id, visibility}} ->
            {:ok, 200, [], %{"id" => id, "owner" => %{"id" => 12345}, "visibility" => visibility}}

          :error ->
            {:ok, 404, [], %{}}
        end
    end)
  end

  defp revoked?(token), do: Repo.get!(Hexpm.OAuth.Token, token.id).revoked_at != nil

  describe "update/3" do
    setup %{workload_identity: workload_identity} do
      %{workload_identity: Repo.preload(workload_identity, package: :repository)}
    end

    test "changes the repositories, workflow and environment, audits it and emails the owners", %{
      user: user,
      package: package,
      workload_identity: workload_identity
    } do
      stub_github(%{"widget" => {67890, "private"}, "gadget" => {70001, "private"}})

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{
                   "repositories" => "widget\ngadget",
                   "workflow" => "publish.yml",
                   "environment" => "release"
                 },
                 audit: audit_data(user)
               )

      assert updated.repositories == [trusted("acme/widget"), trusted("acme/gadget", "70001")]
      assert updated.workflow == "publish.yml"
      assert updated.environment == "release"
      assert updated.repository_owner == "acme"

      reloaded = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
      assert reloaded.repositories == updated.repositories

      log = Repo.get_by!(AuditLog, action: "workload_identity.update")
      assert log.user_id == user.id
      assert log.params["package"]["name"] == package.name
      assert log.params["workflow"] == "publish.yml"
      assert length(log.params["repositories"]) == 2

      assert log.params["previous"]["repositories"] == [
               %{"name" => "acme/widget", "id" => "67890"}
             ]

      assert log.params["previous"]["workflow"] == "release.yml"
      assert log.params["previous"]["environment"] == ""

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity changed on package #{package.name}"
        assert email.text_body =~ "#{user.username} changed a workload identity"
        assert email.text_body =~ "Before:\nGitHub repository: acme/widget\nWorkflow: release.yml"

        assert email.text_body =~
                 "Now:\nGitHub repositories: acme/widget, acme/gadget\nWorkflow: publish.yml\n" <>
                   "Environment: release"

        assert email.to == [{user.username, Hexpm.Accounts.User.email(user, :primary)}]
      end)

      refute_email_sent()
    end

    test "refuses the configuration of another workload identity of the package", %{
      user: user,
      package: package,
      workload_identity: workload_identity
    } do
      insert(:workload_identity,
        package: package,
        repositories: [trusted("acme/gadget", "70001")],
        workflow: "publish.yml"
      )

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "gadget", "workflow" => "publish.yml"},
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:repositories] ==
               "already have a workload identity with this workflow and environment"
    end

    test "keeps the pinned ID of a repository Hex can't see", %{
      user: user,
      workload_identity: workload_identity
    } do
      stub_github(%{})

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget", "workflow" => "publish.yml"},
                 audit: audit_data(user)
               )

      assert updated.repositories == [trusted("acme/widget")]
    end

    test "keeps the pinned IDs of the repositories it names without asking GitHub", %{
      user: user,
      workload_identity: workload_identity
    } do
      expect(Hexpm.HTTP.Mock, :get, 0, fn _url, _headers, _opts -> flunk("asked GitHub") end)

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{
                   "repositories" => "widget",
                   "workflow" => "publish.yml",
                   "environment" => "release"
                 },
                 audit: audit_data(user)
               )

      assert updated.repositories == [trusted("acme/widget")]
      assert updated.workflow == "publish.yml"
    end

    test "only asks GitHub about the repositories it adds", %{
      user: user,
      workload_identity: workload_identity
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        {:ok, 200, [], %{"id" => 70001, "owner" => %{"id" => 12345}, "visibility" => "private"}}
      end)

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget\ngadget", "workflow" => "release.yml"},
                 audit: audit_data(user),
                 before_lookup: fn calls ->
                   send(self(), {:github_calls, calls})
                   :ok
                 end
               )

      assert updated.repositories == [trusted("acme/widget"), trusted("acme/gadget", "70001")]
      assert_received {:github_calls, 1}
    end

    test "uses the pinned owner ID when Hex can't see the repositories it adds", %{
      user: user,
      workload_identity: workload_identity
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        {:ok, 404, [], %{}}
      end)

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget\ngadget 70001", "workflow" => "release.yml"},
                 audit: audit_data(user)
               )

      assert updated.repository_owner_id == "12345"
      assert updated.repositories == [trusted("acme/widget"), trusted("acme/gadget", "70001")]
    end

    test "refuses a repository GitHub now reports under another ID once it removes the environment",
         %{user: user, workload_identity: workload_identity} do
      workload_identity =
        workload_identity |> Ecto.Changeset.change(environment: "release") |> Repo.update!()

      stub_github(%{"widget" => {99999, "private"}})

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget", "workflow" => "release.yml", "environment" => ""},
                 audit: audit_data(user),
                 before_lookup: fn calls ->
                   send(self(), {:github_calls, calls})
                   :ok
                 end
               )

      assert errors_on(changeset)[:repositories] ==
               "acme/widget was deleted and created again on GitHub since it was added. " <>
                 "Remove it and save, then add it again"

      assert_received {:github_calls, 1}

      reloaded = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
      assert reloaded.environment == "release"
      refute_email_sent()
    end

    test "refuses a repository it adds that was renamed or transferred", %{
      user: user,
      workload_identity: workload_identity
    } do
      expect(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        {:ok, 301, [{"location", "https://api.github.com/repositories/70001"}], %{}}
      end)

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget\ngadget", "workflow" => "release.yml"},
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:repositories] ==
               "acme/gadget was renamed or transferred on GitHub. " <>
                 "Replace it with the repository's new name"
    end

    test "refuses a change made to a workload identity someone else changed since", %{
      user: user,
      workload_identity: workload_identity
    } do
      workload_identity
      |> Ecto.Changeset.change(workflow: "other.yml")
      |> Repo.update!()

      assert {:error, :changed} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget", "workflow" => "publish.yml"},
                 audit: audit_data(user)
               )

      reloaded = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
      assert reloaded.workflow == "other.yml"
      refute_email_sent()
    end

    test "refuses a form loaded before another save, without asking GitHub", %{
      user: user,
      workload_identity: workload_identity
    } do
      test_pid = self()

      stub(Hexpm.HTTP.Mock, :get, fn url, _headers, _opts ->
        send(test_pid, {:github, url})
        {:ok, 404, [], %{}}
      end)

      # The form was loaded while the workload identity named widget and gadget
      loaded =
        workload_identity
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_embed(:repositories, [
          trusted("acme/widget"),
          trusted("acme/gadget", "70001")
        ])
        |> Repo.update!()

      stale_version = WorkloadIdentities.version(loaded)

      # Another save removed gadget before the form was submitted
      current =
        loaded
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_embed(:repositories, [trusted("acme/widget")])
        |> Repo.update!()

      assert {:error, :changed} =
               WorkloadIdentities.update(
                 current,
                 %{
                   "repositories" => "widget\ngadget",
                   "workflow" => "release.yml",
                   "environment" => "release",
                   "version" => stale_version
                 },
                 audit: audit_data(user)
               )

      refute_received {:github, _url}

      reloaded = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
      assert reloaded.repositories == [trusted("acme/widget")]
      assert reloaded.environment == ""
      refute Repo.get_by(AuditLog, action: "workload_identity.update")
      refute_email_sent()
    end

    test "saves a form loaded with the current version", %{
      user: user,
      workload_identity: workload_identity
    } do
      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{
                   "repositories" => "widget",
                   "workflow" => "release.yml",
                   "environment" => "release",
                   "version" => WorkloadIdentities.version(workload_identity)
                 },
                 audit: audit_data(user)
               )

      assert updated.environment == "release"
    end

    test "refuses a typed ID that differs from the pinned one", %{
      user: user,
      workload_identity: workload_identity
    } do
      stub_github(%{})

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget 11111"},
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:repositories] ==
               "acme/widget has repository ID 67890. " <>
                 "Remove it and save, then add it again with the new ID"
    end

    test "refuses an owner GitHub now reports under another ID", %{
      user: user,
      workload_identity: workload_identity
    } do
      stub(Hexpm.HTTP.Mock, :get, fn "https://api.github.com/repos/acme/gadget", _, _ ->
        {:ok, 200, [], %{"id" => 70001, "owner" => %{"id" => 999}}}
      end)

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget\ngadget", "workflow" => "publish.yml"},
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:repository_owner] ==
               "is a different GitHub account than when the workload identity was added"
    end

    test "keeps the repository owner and the provider", %{
      user: user,
      workload_identity: workload_identity
    } do
      stub_github(%{"widget" => {67890, "private"}})

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{
                   "provider" => "other",
                   "repository_owner" => "other",
                   "repositories" => "widget",
                   "workflow" => "publish.yml"
                 },
                 audit: audit_data(user)
               )

      assert updated.repository_owner == "acme"
      assert updated.provider == "github"
    end

    test "requires an environment when a repository it adds is public", %{
      user: user,
      workload_identity: workload_identity
    } do
      stub_github(%{"gadget" => {70001, "public"}})

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget\ngadget", "workflow" => "publish.yml"},
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:environment] == "is required because acme/gadget is public"
    end

    test "requires an environment when it removes the environment and a repository is public",
         %{user: user, workload_identity: workload_identity} do
      workload_identity =
        workload_identity |> Ecto.Changeset.change(environment: "release") |> Repo.update!()

      stub_github(%{"widget" => {67890, "public"}})

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget", "workflow" => "release.yml", "environment" => ""},
                 audit: audit_data(user)
               )

      assert errors_on(changeset)[:environment] == "is required because acme/widget is public"
    end

    test "revokes the issued tokens when it removes a repository or changes the workflow or environment",
         %{user: user, package: package, workload_identity: workload_identity} do
      opts = [repository: "hexpm", package: package.name]

      for change <- [
            %{"repositories" => "gadget"},
            %{"workflow" => "publish.yml"},
            %{"environment" => "release"}
          ] do
        identity = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
        WorkloadIdentityHelpers.stub_oidc_discovery(clear_cache: false)

        assert {:ok, token} =
                 mint(opts,
                   repository: hd(identity.repositories).name,
                   repository_id: hd(identity.repositories).id,
                   workflow: identity.workflow,
                   environment: if(identity.environment != "", do: identity.environment)
                 )

        stub_github(%{"widget" => {67890, "private"}, "gadget" => {70001, "private"}})

        params =
          Map.merge(
            %{
              "repositories" => Enum.map_join(identity.repositories, "\n", & &1.name),
              "workflow" => identity.workflow,
              "environment" => identity.environment
            },
            change
          )

        assert {:ok, _updated} =
                 WorkloadIdentities.update(identity, params, audit: audit_data(user))

        assert revoked?(token), "expected #{inspect(change)} to revoke the token"
      end
    end

    test "keeps the issued tokens when it only adds repositories", %{
      user: user,
      package: package,
      workload_identity: workload_identity
    } do
      assert {:ok, token} = mint(repository: "hexpm", package: package.name)
      stub_github(%{"widget" => {67890, "private"}, "gadget" => {70001, "private"}})

      assert {:ok, _updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget\ngadget"},
                 audit: audit_data(user)
               )

      refute revoked?(token)
    end

    test "emails the owners about a change that trusts workflow runs it didn't", %{
      user: user,
      workload_identity: workload_identity
    } do
      for {environment, change} <- [
            {"", %{"repositories" => "widget\ngadget"}},
            {"", %{"workflow" => "publish.yml"}},
            {"release", %{"environment" => "staging"}},
            {"release", %{"environment" => ""}}
          ] do
        identity =
          Hexpm.WorkloadIdentities.WorkloadIdentity
          |> Repo.get!(workload_identity.id)
          |> Ecto.Changeset.change(
            repositories: [trusted("acme/widget")],
            workflow: "release.yml",
            environment: environment
          )
          |> Repo.update!()

        stub_github(%{"widget" => {67890, "private"}, "gadget" => {70001, "private"}})

        params =
          Map.merge(
            %{
              "repositories" => "widget",
              "workflow" => "release.yml",
              "environment" => environment
            },
            change
          )

        assert {:ok, _updated} =
                 WorkloadIdentities.update(identity, params, audit: audit_data(user))

        assert_email_sent(fn email ->
          assert email.subject =~ "Workload identity changed on package"
        end)

        refute_email_sent()
      end
    end

    test "audits a change that only narrows it without emailing anyone", %{
      user: user,
      package: package,
      workload_identity: workload_identity
    } do
      identity =
        workload_identity
        |> Ecto.Changeset.change(
          repositories: [trusted("acme/widget"), trusted("acme/gadget", "70001")]
        )
        |> Repo.update!()

      assert {:ok, token} = mint(repository: "hexpm", package: package.name)

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 identity,
                 %{
                   "repositories" => "widget",
                   "workflow" => "release.yml",
                   "environment" => "release"
                 },
                 audit: audit_data(user)
               )

      assert updated.repositories == [trusted("acme/widget")]
      assert updated.environment == "release"
      assert revoked?(token)
      assert Repo.get_by(AuditLog, action: "workload_identity.update")
      refute_email_sent()
    end

    test "writes no audit log and sends no email when nothing changes", %{
      user: user,
      workload_identity: workload_identity
    } do
      stub_github(%{"widget" => {67890, "private"}})

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{
                   "repositories" => "Widget",
                   "workflow" => "release.yml",
                   "environment" => ""
                 },
                 audit: audit_data(user)
               )

      assert updated.updated_at == workload_identity.updated_at
      assert Repo.aggregate(AuditLog, :count) == 0
      refute_email_sent()
    end

    test "refuses a user who stopped being a full owner during the GitHub lookup", %{
      user: user,
      package: package,
      workload_identity: workload_identity
    } do
      stub_github(%{"widget" => {67890, "private"}})

      transfer = fn _calls ->
        Repo.delete_all(
          from(o in Hexpm.Repository.PackageOwner, where: o.package_id == ^package.id)
        )

        insert(:package_owner, package: package, user: insert(:user), level: "full")
        :ok
      end

      assert {:error, :not_owner} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget", "workflow" => "publish.yml"},
                 audit: audit_data(user),
                 before_lookup: transfer
               )

      reloaded = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
      assert reloaded.workflow == "release.yml"
    end

    test "returns not found for a workload identity removed in the meantime", %{
      user: user,
      workload_identity: workload_identity
    } do
      stub_github(%{"widget" => {67890, "private"}})
      Repo.delete!(workload_identity)

      assert {:error, :not_found} =
               WorkloadIdentities.update(
                 workload_identity,
                 %{"repositories" => "widget", "workflow" => "publish.yml"},
                 audit: audit_data(user)
               )

      assert Repo.aggregate(AuditLog, :count) == 0
      refute_email_sent()
    end
  end

  describe "update/3 for an organization" do
    setup do
      admin = insert(:user)
      other_admin = insert(:user)
      co_owner = insert(:user)

      organization =
        insert(:organization,
          organization_users: [
            build(:organization_user, user: admin, role: "admin"),
            build(:organization_user, user: other_admin, role: "admin")
          ]
        )

      repository = insert(:repository, organization: organization, name: organization.name)

      owned_one =
        insert(:package,
          name: "owned_one",
          package_owners: [
            build(:package_owner, user: organization.user, level: "full"),
            build(:package_owner, user: co_owner, level: "full")
          ]
        )

      owned_two =
        insert(:package,
          name: "owned_two",
          package_owners: [
            build(:package_owner, user: organization.user, level: "full"),
            build(:package_owner, user: co_owner, level: "full")
          ]
        )

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          repositories: [trusted("acme/widget")],
          workflow: "release.yml",
          covers_public: true,
          public_packages: ["owned_one"]
        )

      stub_github(%{"widget" => {67890, "private"}, "gadget" => {70001, "private"}})

      %{
        admin: admin,
        other_admin: other_admin,
        co_owner: co_owner,
        organization: organization,
        repository: repository,
        owned_one: owned_one,
        owned_two: owned_two,
        identity: identity
      }
    end

    defp organization_params(params) do
      Map.merge(
        %{
          "repositories" => "widget",
          "workflow" => "release.yml",
          "environment" => "",
          "covers_private" => "true",
          "packages" => "",
          "covers_public" => "true",
          "public_packages" => "owned_one"
        },
        params
      )
    end

    test "changes the packages, audits it and emails the admins without revoking tokens", %{
      admin: admin,
      other_admin: other_admin,
      organization: organization,
      repository: repository,
      identity: identity
    } do
      identity =
        identity
        |> Ecto.Changeset.change(packages: ["widget"])
        |> Repo.update!()

      WorkloadIdentityHelpers.stub_oidc_discovery()
      assert {:ok, token} = mint(repository: repository.name, package: "widget")

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{"packages" => ""}),
                 audit: audit_data(admin)
               )

      assert updated.packages == nil
      assert updated.role == "write"
      refute revoked?(token)

      log = Repo.get_by!(AuditLog, action: "organization.workload_identity.update")
      assert log.organization_id == organization.id
      assert log.params["packages"] == nil
      assert log.params["previous"]["packages"] == ["widget"]
      assert log.params["previous"]["public_packages"] == ["owned_one"]

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity changed in organization #{organization.name}"
        assert email.text_body =~ "#{admin.username} changed a workload identity"
        assert email.text_body =~ "Before:\nRole: write"
        assert email.text_body =~ "Private packages: widget"
        assert email.text_body =~ "Private packages: all"

        assert Enum.sort(Enum.map(email.to, &elem(&1, 1))) ==
                 Enum.sort([
                   Hexpm.Accounts.User.email(admin, :primary),
                   Hexpm.Accounts.User.email(other_admin, :primary)
                 ])
      end)

      refute_email_sent()
    end

    test "audits a change that only narrows it without emailing anyone", %{
      admin: admin,
      identity: identity
    } do
      identity =
        identity
        |> Ecto.Changeset.change(
          repositories: [trusted("acme/widget", "67890"), trusted("acme/gadget", "67891")],
          public_packages: ["owned_one", "owned_two"]
        )
        |> Repo.update!()

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{
                   "environment" => "release",
                   "packages" => "widget",
                   "public_packages" => "owned_two"
                 }),
                 audit: audit_data(admin)
               )

      assert Enum.map(updated.repositories, & &1.name) == ["acme/widget"]
      assert updated.environment == "release"
      assert updated.packages == ["widget"]
      assert updated.public_packages == ["owned_two"]
      assert Repo.get_by(AuditLog, action: "organization.workload_identity.update")
      refute_email_sent()
    end

    test "doesn't tell the other owners whose public packages it only stops publishing", %{
      admin: admin,
      identity: identity
    } do
      identity =
        identity
        |> Ecto.Changeset.change(
          packages: ["widget"],
          public_packages: ["owned_one", "owned_two"]
        )
        |> Repo.update!()

      assert {:ok, _updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{"packages" => "", "public_packages" => "owned_two"}),
                 audit: audit_data(admin)
               )

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity changed in organization"
      end)

      refute_email_sent()
    end

    test "tells the other owners of the public packages it starts publishing", %{
      admin: admin,
      co_owner: co_owner,
      organization: organization,
      identity: identity
    } do
      assert {:ok, _updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{"public_packages" => "owned_one, owned_two"}),
                 audit: audit_data(admin)
               )

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity changed in organization"
      end)

      assert_email_sent(fn email ->
        assert Enum.map(email.to, &elem(&1, 1)) == [Hexpm.Accounts.User.email(co_owner, :primary)]

        assert email.subject =~
                 "Workload identity of organization #{organization.name} changed for owned_two"

        assert email.text_body =~ "It can now publish:\nowned_two"
        refute email.text_body =~ "It still publishes"
        refute email.text_body =~ "Before:"
        assert email.text_body =~ "Public packages: owned_two"
      end)

      refute_email_sent()
    end

    test "tells the other owners of the public packages it keeps publishing from changed workflows",
         %{admin: admin, co_owner: co_owner, identity: identity} do
      assert {:ok, _updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{"workflow" => "publish.yml"}),
                 audit: audit_data(admin)
               )

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity changed in organization"
      end)

      assert_email_sent(fn email ->
        assert Enum.map(email.to, &elem(&1, 1)) == [Hexpm.Accounts.User.email(co_owner, :primary)]
        assert email.subject =~ "changed for owned_one"

        assert email.text_body =~
                 "It still publishes these, from the changed workflows below:\nowned_one"

        assert email.text_body =~ "Workflow: release.yml"
        assert email.text_body =~ "Workflow: publish.yml"
      end)

      refute_email_sent()
    end

    test "tells the other owners of the public packages it stops publishing", %{
      admin: admin,
      co_owner: co_owner,
      identity: identity
    } do
      assert {:ok, _updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{"public_packages" => "owned_two"}),
                 audit: audit_data(admin)
               )

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity changed in organization"
      end)

      assert_email_sent(fn email ->
        assert Enum.map(email.to, &elem(&1, 1)) == [Hexpm.Accounts.User.email(co_owner, :primary)]
        assert email.subject =~ "changed for owned_one, owned_two"
        refute email.text_body =~ "It still publishes"
        assert email.text_body =~ "It can now publish:\nowned_two"
        assert email.text_body =~ "It can no longer publish:\nowned_one"
      end)

      refute_email_sent()
    end

    test "only tells the other owners about a change to the packages they own", %{
      admin: admin,
      identity: identity
    } do
      identity =
        identity
        |> Ecto.Changeset.change(packages: ["private_one"])
        |> Repo.update!()

      assert {:ok, _updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{"packages" => "private_one private_two"}),
                 audit: audit_data(admin)
               )

      assert_email_sent(fn email ->
        assert email.subject =~ "Workload identity changed in organization"
      end)

      refute_email_sent()
    end

    test "only checks the public package names the change adds", %{
      admin: admin,
      identity: identity
    } do
      someone_elses = insert(:package, package_owners: [build(:package_owner, user: admin)])
      later = insert(:package, package_owners: [build(:package_owner, user: admin)])

      identity =
        identity
        |> Ecto.Changeset.change(public_packages: ["owned_one", someone_elses.name])
        |> Repo.update!()

      assert {:ok, _updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{
                   "workflow" => "publish.yml",
                   "public_packages" => "owned_one #{someone_elses.name}"
                 }),
                 audit: audit_data(admin)
               )

      identity = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, identity.id)

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{
                   "workflow" => "publish.yml",
                   "public_packages" => "owned_one #{someone_elses.name} #{later.name}"
                 }),
                 audit: audit_data(admin)
               )

      assert errors_on(changeset)[:public_packages] ==
               "must be public packages the organization owns, not #{later.name}"
    end

    test "matches every repository of the owner once the read role lists none", %{
      admin: admin,
      organization: organization,
      repository: repository
    } do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          repositories: [trusted("acme/widget")]
        )

      assert {:ok, updated} =
               WorkloadIdentities.update(identity, %{"repositories" => ""},
                 audit: audit_data(admin)
               )

      assert updated.repositories == []

      WorkloadIdentityHelpers.stub_oidc_discovery()

      assert {:ok, token} =
               mint([repository: repository.name],
                 repository: "acme/gizmo",
                 repository_id: "70002",
                 workflow: "ci.yml"
               )

      assert token.workload_identity_id == identity.id
    end

    defp without_billing(organization) do
      organization
      |> Ecto.Changeset.change(billing_active: false, trial_end: nil)
      |> Repo.update!()
    end

    defp reload(identity), do: Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, identity.id)

    test "keeps private coverage and its packages without billing when it changes the repositories",
         %{admin: admin, organization: organization, identity: identity} do
      identity =
        identity
        |> Ecto.Changeset.change(packages: ["private_one"])
        |> Repo.update!()

      without_billing(organization)

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 reload(identity),
                 organization_params(%{
                   "repositories" => "widget\ngadget",
                   "packages" => "private_one"
                 }),
                 audit: audit_data(admin)
               )

      assert updated.covers_private
      assert updated.packages == ["private_one"]
      assert updated.repositories == [trusted("acme/widget"), trusted("acme/gadget", "70001")]
    end

    test "refuses to turn private packages on without billing", %{
      admin: admin,
      organization: organization,
      identity: identity
    } do
      identity =
        identity
        |> Ecto.Changeset.change(covers_private: false, packages: [])
        |> Repo.update!()

      without_billing(organization)

      assert {:error, changeset} =
               WorkloadIdentities.update(
                 reload(identity),
                 organization_params(%{"covers_private" => "true"}),
                 audit: audit_data(admin)
               )

      assert errors_on(changeset)[:covers_private] ==
               "private packages need an active billing subscription"

      refute reload(identity).covers_private
    end

    test "changes a read identity without billing", %{
      admin: admin,
      organization: organization
    } do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          repositories: [trusted("acme/widget"), trusted("acme/gadget", "70001")]
        )

      without_billing(organization)

      assert {:ok, updated} =
               WorkloadIdentities.update(reload(identity), %{"repositories" => "widget"},
                 audit: audit_data(admin)
               )

      assert updated.repositories == [trusted("acme/widget")]
    end

    test "revokes the tokens of a read identity for every repository once it lists repositories",
         %{admin: admin, organization: organization, repository: repository} do
      identity =
        insert(:organization_workload_identity, organization: organization, repositories: [])

      WorkloadIdentityHelpers.stub_oidc_discovery()

      assert {:ok, token} =
               mint([repository: repository.name],
                 repository: "acme/gizmo",
                 repository_id: "70002",
                 workflow: "ci.yml"
               )

      stub_github(%{"widget" => {67890, "private"}})

      assert {:ok, updated} =
               WorkloadIdentities.update(identity, %{"repositories" => "widget"},
                 audit: audit_data(admin)
               )

      assert updated.repositories == [trusted("acme/widget")]
      assert revoked?(token)
    end

    test "keeps the tokens of a read identity that stops listing repositories", %{
      admin: admin,
      organization: organization,
      repository: repository
    } do
      identity =
        insert(:organization_workload_identity,
          organization: organization,
          repositories: [trusted("acme/widget")]
        )

      WorkloadIdentityHelpers.stub_oidc_discovery()
      assert {:ok, token} = mint([repository: repository.name], workflow: "ci.yml")

      assert {:ok, updated} =
               WorkloadIdentities.update(identity, %{"repositories" => ""},
                 audit: audit_data(admin)
               )

      assert updated.repositories == []
      refute revoked?(token)
    end

    test "keeps the tokens and emails no one when only the environment's case changes",
         %{admin: admin, repository: repository, identity: identity} do
      identity =
        identity
        |> Ecto.Changeset.change(environment: "Release")
        |> Repo.update!()

      WorkloadIdentityHelpers.stub_oidc_discovery()
      assert {:ok, token} = mint([repository: repository.name], environment: "release")

      assert {:ok, updated} =
               WorkloadIdentities.update(
                 identity,
                 organization_params(%{"environment" => "RELEASE"}),
                 audit: audit_data(admin)
               )

      assert updated.environment == "RELEASE"
      refute revoked?(token)
      refute_email_sent()
    end
  end

  describe "version/1" do
    test "is the same for the same configuration", %{workload_identity: workload_identity} do
      reloaded = Repo.get!(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
      assert WorkloadIdentities.version(reloaded) == WorkloadIdentities.version(workload_identity)

      reordered = %{
        workload_identity
        | repositories: [trusted("acme/gadget", "1"), trusted("acme/widget")]
      }

      in_order = %{
        workload_identity
        | repositories: [trusted("acme/widget"), trusted("acme/gadget", "1")]
      }

      assert WorkloadIdentities.version(reordered) == WorkloadIdentities.version(in_order)

      touched = %{workload_identity | updated_at: DateTime.utc_now(), id: workload_identity.id}
      assert WorkloadIdentities.version(touched) == WorkloadIdentities.version(workload_identity)
    end

    test "changes with the repositories, workflow, environment and coverage", %{
      workload_identity: workload_identity
    } do
      version = WorkloadIdentities.version(workload_identity)

      changes = [
        repositories: [trusted("acme/gadget")],
        repositories: [trusted("acme/widget", "1")],
        workflow: "publish.yml",
        environment: "release",
        covers_private: false,
        packages: ["foo"],
        covers_public: true,
        public_packages: ["bar"]
      ]

      for {field, value} <- changes do
        changed = Map.put(workload_identity, field, value)

        refute WorkloadIdentities.version(changed) == version,
               "the version didn't change with #{field}"
      end
    end
  end

  describe "unowned_public_packages/1" do
    test "lists the public packages the identity names that its organization doesn't own" do
      organization = insert(:organization)

      owned =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )

      maintained =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "maintainer")]
        )

      someone_elses =
        insert(:package, package_owners: [build(:package_owner, user: insert(:user))])

      identity =
        insert(:organization_workload_identity,
          organization: organization,
          role: "write",
          workflow: "release.yml",
          covers_public: true,
          public_packages: [owned.name, maintained.name, someone_elses.name, "missing"]
        )

      assert WorkloadIdentities.unowned_public_packages(identity) == [
               maintained.name,
               someone_elses.name,
               "missing"
             ]

      assert WorkloadIdentities.unowned_public_packages(%{identity | public_packages: nil}) == []

      assert WorkloadIdentities.unowned_public_packages(%{
               identity
               | covers_public: false,
                 public_packages: nil
             }) == []
    end
  end
end

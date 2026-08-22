defmodule Hexpm.Repository.PolicyBuilderTest do
  use Hexpm.DataCase, async: false
  use Oban.Testing, repo: Hexpm.RepoBase

  alias Hexpm.Repository.{Policies, PolicyBuilder}
  alias Hexpm.Security.Advisory
  alias Hexpm.Security.AdvisoryAffectedVersion

  setup do
    user = insert(:user)
    organization = insert(:organization)
    audit_data = audit_data(user)
    package = insert(:package, name: "phoenix")

    Repo.insert!(%Advisory{
      id: "GHSA-policy-build",
      summary: "policy builder advisory",
      aliases: ["CVE-2026-6000"],
      published_at: ~U[2026-01-01 00:00:00Z],
      modified_at: ~U[2026-01-01 00:00:00Z]
    })

    Repo.insert!(%AdvisoryAffectedVersion{
      advisory_id: "GHSA-policy-build",
      package_id: package.id,
      requirement: Version.parse_requirement!("< 1.8.0")
    })

    Repo.insert_all("security_advisory_affected_packages", [
      %{advisory_id: "GHSA-policy-build", package_id: package.id}
    ])

    {:ok, %{policy: policy}} =
      Policies.create(
        organization,
        %{
          "name" => "strict-prod",
          "visibility" => "private",
          "repositories" => [
            %{
              "repository" => "hexpm",
              "cooldown" => "14d",
              "advisory_min_severity" => 3,
              "retirement_reasons" => [1, 2],
              "overrides" => [
                %{"action" => "deny", "package" => "badlib", "comment" => "never approved"},
                %{
                  "action" => "allow",
                  "package" => "phoenix",
                  "requirement" => "== 1.7.10",
                  "comment" => "approved release"
                },
                %{
                  "action" => "advisory",
                  "package" => "phoenix",
                  "requirement" => ">= 1.7.0 and < 1.8.0",
                  "advisory_id" => "CVE-2026-6000",
                  "comment" => "approved migration"
                },
                %{
                  "action" => "retirement",
                  "package" => "old_package",
                  "retirement_reason" => 2
                },
                %{
                  "action" => "cooldown",
                  "package" => "fresh_package",
                  "requirement" => "== 1.0.0",
                  "comment" => "release provenance verified"
                }
              ]
            },
            %{"repository" => organization.name}
          ]
        },
        audit: audit_data
      )

    %{organization: organization, policy: policy, audit_data: audit_data}
  end

  describe "build/1" do
    test "produces a signed, gzipped Policy protobuf with per-repository tabs",
         %{organization: org, policy: policy} do
      policy = Hexpm.Repo.preload(policy, :organization)
      contents = PolicyBuilder.build(policy)

      assert is_binary(contents)
      assert byte_size(contents) > 0

      public_key = Application.fetch_env!(:hexpm, :public_key)

      assert {:ok,
              %{
                repository: repo_name,
                name: "strict-prod",
                visibility: :VISIBILITY_PRIVATE,
                repositories: repositories
              }} = :hex_registry.unpack_policy(contents, org.name, "strict-prod", public_key)

      assert repo_name == org.name

      hexpm = Enum.find(repositories, &(&1.repository == "hexpm"))
      assert hexpm.restriction.advisory_min_severity == :SEVERITY_HIGH
      assert hexpm.restriction.retirement_reasons == [:RETIRED_INVALID, :RETIRED_SECURITY]
      assert hexpm.restriction.cooldown == "14d"

      assert [deny, allow, advisory, retirement, cooldown] = hexpm.overrides
      assert deny.action == :OVERRIDE_ACTION_DENY
      assert deny.ref.package == "badlib"
      assert deny.comment == "never approved"
      assert allow.action == :OVERRIDE_ACTION_ALLOW
      assert allow.ref.package == "phoenix"
      assert allow.ref.requirement == "== 1.7.10"
      assert allow.comment == "approved release"
      assert advisory.action == :OVERRIDE_ACTION_ADVISORY
      assert advisory.ref.package == "phoenix"
      assert advisory.ref.requirement == ">= 1.7.0 and < 1.8.0"
      assert advisory.advisory_id == "CVE-2026-6000"
      assert advisory.comment == "approved migration"
      assert retirement.action == :OVERRIDE_ACTION_RETIREMENT
      assert retirement.ref.package == "old_package"
      assert retirement.retirement_reason == :RETIRED_SECURITY
      assert Map.get(retirement, :comment, :undefined) == :undefined
      assert cooldown.action == :OVERRIDE_ACTION_COOLDOWN
      assert cooldown.ref.package == "fresh_package"
      assert cooldown.ref.requirement == "== 1.0.0"
      assert cooldown.comment == "release provenance verified"

      org_tab = Enum.find(repositories, &(&1.repository == org.name))
      assert org_tab.overrides == []
      refute Map.has_key?(org_tab, :restriction) and org_tab.restriction != :undefined
    end

    test "omits the restriction when a tab sets no limits",
         %{organization: org, audit_data: audit_data} do
      {:ok, %{policy: policy}} =
        Policies.create(org, %{"name" => "open-pol", "visibility" => "public"}, audit: audit_data)

      policy = Hexpm.Repo.preload(policy, :organization)
      public_key = Application.fetch_env!(:hexpm, :public_key)

      {:ok, %{repositories: repositories}} =
        :hex_registry.unpack_policy(PolicyBuilder.build(policy), org.name, "open-pol", public_key)

      hexpm = Enum.find(repositories, &(&1.repository == "hexpm"))
      assert Map.get(hexpm, :restriction, :undefined) == :undefined
    end

    test "a public policy publishes only the hexpm tab", %{
      organization: org,
      audit_data: audit_data
    } do
      {:ok, %{policy: policy}} =
        Policies.create(
          org,
          %{
            "name" => "public-pol",
            "visibility" => "public",
            "repositories" => [
              %{"repository" => "hexpm", "cooldown" => "14d"},
              %{"repository" => org.name, "cooldown" => "7d"}
            ]
          },
          audit: audit_data
        )

      policy = Hexpm.Repo.preload(policy, :organization)
      public_key = Application.fetch_env!(:hexpm, :public_key)

      {:ok, %{repositories: repositories}} =
        :hex_registry.unpack_policy(
          PolicyBuilder.build(policy),
          org.name,
          "public-pol",
          public_key
        )

      assert Enum.map(repositories, & &1.repository) == ["hexpm"]
    end
  end

  describe "rebuild/1" do
    test "uploads the payload to repo_bucket and verifies a private policy with the repository token",
         %{organization: org, policy: policy} do
      policy = Hexpm.Repo.preload(policy, :organization)
      assert :ok = PolicyBuilder.rebuild(policy)

      stored = Hexpm.Store.get(:repo_bucket, "repos/#{org.name}/policies/strict-prod", [])
      assert is_binary(stored)

      public_key = Application.fetch_env!(:hexpm, :public_key)

      assert {:ok, %{name: "strict-prod"}} =
               :hex_registry.unpack_policy(stored, org.name, "strict-prod", public_key)

      etag = ~s("#{Base.encode16(:crypto.hash(:md5, stored), case: :lower)}")

      assert_enqueued(
        worker: Hexpm.CDN.PurgeWorker,
        args: %{
          "service" => "fastly_hexrepo",
          "keys" => ["policy/#{org.name}/strict-prod"],
          "verify" => [
            %{
              "url" => "http://localhost:5000/repos/#{org.name}/policies/strict-prod",
              "etag" => etag,
              "repository" => org.name
            }
          ]
        }
      )
    end

    test "verifies the purge of a public policy", %{organization: org, audit_data: audit_data} do
      {:ok, _} =
        Policies.create(org, %{"name" => "open-pol", "visibility" => "public"}, audit: audit_data)

      stored = Hexpm.Store.get(:repo_bucket, "repos/#{org.name}/policies/open-pol", [])
      etag = ~s("#{Base.encode16(:crypto.hash(:md5, stored), case: :lower)}")

      assert_enqueued(
        worker: Hexpm.CDN.PurgeWorker,
        args: %{
          "keys" => ["policy/#{org.name}/open-pol"],
          "verify" => [
            %{
              "url" => "http://localhost:5000/repos/#{org.name}/policies/open-pol",
              "etag" => etag
            }
          ]
        }
      )
    end

    test "republishes a tab without the overrides an update removed",
         %{organization: org, policy: policy, audit_data: audit_data} do
      params = %{
        "repositories" =>
          Enum.map(policy.repositories, fn tab ->
            %{"id" => tab.id, "repository" => tab.repository}
          end)
      }

      {:ok, _} = Policies.update(policy, params, audit: audit_data)

      stored = Hexpm.Store.get(:repo_bucket, "repos/#{org.name}/policies/strict-prod", [])
      public_key = Application.fetch_env!(:hexpm, :public_key)

      assert {:ok, %{repositories: repositories}} =
               :hex_registry.unpack_policy(stored, org.name, "strict-prod", public_key)

      assert Enum.find(repositories, &(&1.repository == "hexpm")).overrides == []
    end

    test "acquires and releases the advisory lock cleanly",
         %{organization: org, policy: policy} do
      previous = Application.get_env(:hexpm, :skip_advisory_locks, false)
      Application.put_env(:hexpm, :skip_advisory_locks, false)

      try do
        policy = Hexpm.Repo.preload(policy, :organization)
        assert :ok = PolicyBuilder.rebuild(policy)
        assert :ok = PolicyBuilder.rebuild(policy)

        stored = Hexpm.Store.get(:repo_bucket, "repos/#{org.name}/policies/strict-prod", [])
        assert is_binary(stored)
      after
        Application.put_env(:hexpm, :skip_advisory_locks, previous)
      end
    end
  end

  describe "delete/1" do
    test "removes the policy object from the bucket",
         %{organization: org, policy: policy} do
      policy = Hexpm.Repo.preload(policy, :organization)
      :ok = PolicyBuilder.rebuild(policy)

      assert :ok = PolicyBuilder.delete(policy)
      refute Hexpm.Store.get(:repo_bucket, "repos/#{org.name}/policies/strict-prod", [])
    end
  end

  describe "private policy" do
    test "uses private cache-control", %{organization: org, audit_data: audit_data} do
      {:ok, %{policy: policy}} =
        Policies.create(
          org,
          %{"name" => "private-pol", "visibility" => "private"},
          audit: audit_data
        )

      policy = Hexpm.Repo.preload(policy, :organization)
      assert :ok = PolicyBuilder.rebuild(policy)

      stored = Hexpm.Store.get(:repo_bucket, "repos/#{org.name}/policies/private-pol", [])
      assert is_binary(stored)
    end
  end
end

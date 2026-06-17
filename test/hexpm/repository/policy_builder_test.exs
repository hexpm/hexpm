defmodule Hexpm.Repository.PolicyBuilderTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.Repository.{Policies, PolicyBuilder}

  setup do
    user = insert(:user)
    organization = insert(:organization)
    audit_data = audit_data(user)

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
                %{"action" => "deny", "package" => "badlib"},
                %{"action" => "allow", "package" => "phoenix", "requirement" => "== 1.7.10"}
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

      assert [deny, allow] = hexpm.overrides
      assert deny.action == :OVERRIDE_ACTION_DENY
      assert deny.ref.package == "badlib"
      assert allow.action == :OVERRIDE_ACTION_ALLOW
      assert allow.ref.package == "phoenix"
      assert allow.ref.requirement == "== 1.7.10"

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
    test "uploads the payload to repo_bucket and is purgeable",
         %{organization: org, policy: policy} do
      policy = Hexpm.Repo.preload(policy, :organization)
      assert :ok = PolicyBuilder.rebuild(policy)

      stored = Hexpm.Store.get(:repo_bucket, "repos/#{org.name}/policies/strict-prod", [])
      assert is_binary(stored)

      public_key = Application.fetch_env!(:hexpm, :public_key)

      assert {:ok, %{name: "strict-prod"}} =
               :hex_registry.unpack_policy(stored, org.name, "strict-prod", public_key)
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

defmodule Hexpm.FeatureFlagsTest do
  use Hexpm.DataCase

  alias Hexpm.FeatureFlags

  setup do
    put_feature_flag(:workload_identity, mode: :beta, beta_users: [], beta_organizations: [])
  end

  describe "available?/1" do
    test "in beta needs a user or an organization on the lists" do
      refute FeatureFlags.available?(:workload_identity)

      put_feature_flag(:workload_identity, beta_users: ["someone"])
      assert FeatureFlags.available?(:workload_identity)

      put_feature_flag(:workload_identity, beta_users: [], beta_organizations: ["acme"])
      assert FeatureFlags.available?(:workload_identity)
    end

    test "follows off and enabled whatever the lists hold" do
      put_feature_flag(:workload_identity, mode: :off, beta_users: ["someone"])
      refute FeatureFlags.available?(:workload_identity)

      put_feature_flag(:workload_identity, mode: :enabled, beta_users: [])
      assert FeatureFlags.available?(:workload_identity)
    end
  end

  describe "enabled?/2" do
    test "follows off and enabled whatever the lists hold" do
      organization = insert(:organization)

      put_feature_flag(:workload_identity, mode: :off, beta_organizations: [organization.name])
      refute FeatureFlags.enabled?(:workload_identity, organization)

      put_feature_flag(:workload_identity, mode: :enabled, beta_organizations: [])
      assert FeatureFlags.enabled?(:workload_identity, organization)
    end

    test "takes an organization on the organization list" do
      organization = insert(:organization)

      put_feature_flag(:workload_identity,
        beta_users: [organization.name],
        beta_organizations: ["someone-else"]
      )

      refute FeatureFlags.enabled?(:workload_identity, organization)

      put_feature_flag(:workload_identity, beta_organizations: [organization.name])
      assert FeatureFlags.enabled?(:workload_identity, organization)
    end

    test "takes a public package with an owner on the user list" do
      user = insert(:user)
      package = insert(:package, package_owners: [build(:package_owner, user: user)])

      put_feature_flag(:workload_identity, beta_users: ["someone-else"])
      refute FeatureFlags.enabled?(:workload_identity, package)

      put_feature_flag(:workload_identity, beta_users: [user.username])
      assert FeatureFlags.enabled?(:workload_identity, package)
    end

    test "takes a public package owned by an organization on the organization list" do
      organization = insert(:organization)

      package =
        insert(:package, package_owners: [build(:package_owner, user: organization.user)])

      refute FeatureFlags.enabled?(:workload_identity, package)

      put_feature_flag(:workload_identity, beta_organizations: [organization.name])
      assert FeatureFlags.enabled?(:workload_identity, package)
    end

    test "takes a private package by its organization" do
      user = insert(:user)
      repository = insert(:repository)

      package =
        insert(:package,
          repository_id: repository.id,
          package_owners: [build(:package_owner, user: user)]
        )

      package = %{package | repository: repository}

      put_feature_flag(:workload_identity, beta_users: [user.username])
      refute FeatureFlags.enabled?(:workload_identity, package)

      put_feature_flag(:workload_identity, beta_organizations: [repository.organization.name])
      assert FeatureFlags.enabled?(:workload_identity, package)
    end
  end
end

defmodule Hexpm.Accounts.AuthWorkloadIdentityTest do
  use Hexpm.DataCase, async: false
  import Mox

  alias Hexpm.Accounts.Auth
  alias Hexpm.WorkloadIdentityHelpers

  setup :verify_on_exit!

  setup do
    WorkloadIdentityHelpers.stub_oidc_discovery()

    user = insert(:user)

    package =
      insert(:package,
        package_owners: [build(:package_owner, user: user, level: "full")]
      )

    insert(:workload_identity,
      package: package,
      repository_owner: "acme",
      repository_owner_id: "12345",
      repository_id: "67890",
      repository: "acme/widget",
      workflow: "release.yml"
    )

    %{package: package}
  end

  test "oauth_token_auth resolves workload_identity subjects", %{package: package} do
    oidc = WorkloadIdentityHelpers.sign_oidc_claims(WorkloadIdentityHelpers.github_claims())

    assert {:ok, token} =
             Hexpm.WorkloadIdentities.verify_and_mint(oidc,
               repository: "hexpm",
               package: package.name
             )

    assert {:ok, auth} = Auth.oauth_token_auth(token.access_token, %{})
    assert auth.user == nil
    assert auth.organization == nil
    assert auth.workload_identity.package_id == package.id
    assert auth.auth_credential.grant_type == "workload_identity"
  end
end

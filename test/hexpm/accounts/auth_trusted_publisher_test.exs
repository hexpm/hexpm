defmodule Hexpm.Accounts.AuthTrustedPublisherTest do
  use Hexpm.DataCase, async: false
  import Mox

  alias Hexpm.Accounts.Auth
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

    insert(:trusted_publisher,
      package: package,
      repository_owner: "acme",
      repository_owner_id: "12345",
      repository_id: "67890",
      repository: "acme/widget",
      workflow: "release.yml"
    )

    %{package: package}
  end

  test "oauth_token_auth resolves trusted_publisher subjects", %{package: package} do
    oidc = TrustedPublisherHelpers.sign_oidc_claims(TrustedPublisherHelpers.github_claims())

    assert {:ok, token} =
             Hexpm.TrustedPublishers.verify_and_mint(oidc,
               repository: "hexpm",
               package: package.name
             )

    assert {:ok, auth} = Auth.oauth_token_auth(token.access_token, %{})
    assert auth.user == nil
    assert auth.organization == nil
    assert auth.trusted_publisher.package_id == package.id
    assert auth.auth_credential.grant_type == "trusted_publisher"
  end
end

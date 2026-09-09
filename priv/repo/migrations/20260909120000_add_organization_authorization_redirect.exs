defmodule Hexpm.RepoBase.Migrations.AddOrganizationAuthorizationRedirect do
  use Ecto.Migration

  def change do
    alter table(:organization_sso_authorizations) do
      add :redirect_uri, :text
      add :state, :text
    end

    create constraint(:organization_sso_authorizations, :authorization_redirect_state,
             check: "(redirect_uri IS NULL) = (state IS NULL)"
           )
  end
end

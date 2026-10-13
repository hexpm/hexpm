defmodule Hexpm.Accounts.SSO.Features do
  alias Hexpm.Accounts.Organization
  alias Hexpm.FeatureFlags

  @doc """
  Whether an organization may configure SSO.
  """
  def enabled?(%Organization{} = organization) do
    if FeatureFlags.mode(:organization_sso) == :enabled do
      Application.fetch_env!(:hexpm, :organization_sso)[:all_organizations] ||
        Organization.billing_active?(organization)
    else
      active?(organization)
    end
  end

  @doc """
  Whether SSO may act for an organization that has already configured it.

  Configuring SSO takes an active subscription; being governed by it does not.
  A lapsed card must not quietly turn an organization's access control off, and
  must not lock its members out of authenticating either, so this drops the
  billing check and keeps the kill switch and the beta allowlist.
  """
  def active?(%Organization{} = organization),
    do: FeatureFlags.enabled?(:organization_sso, organization)

  def available?, do: FeatureFlags.available?(:organization_sso)
end

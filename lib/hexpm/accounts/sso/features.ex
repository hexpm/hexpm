defmodule Hexpm.Accounts.SSO.Features do
  alias Hexpm.Accounts.Organization

  @doc """
  Whether an organization may configure SSO.
  """
  def enabled?(%Organization{name: name} = organization) do
    case config()[:mode] do
      :off -> false
      :beta -> name in config()[:beta_organizations]
      :enabled -> config()[:all_organizations] || Organization.billing_active?(organization)
    end
  end

  @doc """
  Whether SSO may act for an organization that has already configured it.

  Configuring SSO takes an active subscription; being governed by it does not.
  A lapsed card must not quietly turn an organization's access control off, and
  must not lock its members out of authenticating either, so this drops the
  billing check and keeps the kill switch and the beta allowlist.
  """
  def active?(%Organization{name: name}) do
    case config()[:mode] do
      :off -> false
      :beta -> name in config()[:beta_organizations]
      :enabled -> true
    end
  end

  def available? do
    case config()[:mode] do
      :off -> false
      :beta -> config()[:beta_organizations] != []
      :enabled -> true
    end
  end

  defp config do
    Application.fetch_env!(:hexpm, :organization_sso)
  end
end

defmodule Hexpm.Accounts.SSO.Features do
  alias Hexpm.Accounts.Organization

  def enabled?(%Organization{name: name} = organization) do
    case config()[:mode] do
      :off -> false
      :beta -> name in config()[:beta_organizations]
      :enabled -> config()[:all_organizations] || Organization.billing_active?(organization)
    end
  end

  def mode, do: config()[:mode]

  defp config do
    Application.fetch_env!(:hexpm, :organization_sso)
  end
end

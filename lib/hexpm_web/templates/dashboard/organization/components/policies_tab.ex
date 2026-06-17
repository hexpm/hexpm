defmodule HexpmWeb.Dashboard.Organization.Components.PoliciesTab do
  @moduledoc """
  Policies tab content for the organization dashboard. Wraps the shared
  PolicyListCard with organization-scoped data.
  """
  use Phoenix.Component

  import HexpmWeb.Dashboard.Policy.Components.PolicyListCard, only: [policy_list_card: 1]

  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :policies, :list, required: true
  attr :policy_stats, :map, default: %{}

  def policies_tab(assigns) do
    ~H"""
    <.policy_list_card
      current_user={@current_user}
      organization={@organization}
      policies={@policies}
      policy_stats={@policy_stats}
    />
    """
  end
end

defmodule HexpmWeb.Dashboard.Organization.Components.KeysTab do
  @moduledoc """
  Keys tab content for the organization dashboard.
  Wraps the shared KeyManagementCard with organization-scoped paths and context.
  """
  use Phoenix.Component

  import HexpmWeb.Dashboard.Key.Components.KeyManagementCard, only: [key_management_card: 1]

  attr :csrf_token, :string, required: true
  attr :create_key_path, :string, required: true
  attr :delete_key_path, :string, required: true
  attr :generated_key, :map, default: nil
  attr :key_changeset, :any, required: true
  attr :keys, :list, required: true
  attr :organization, :map, required: true
  attr :packages, :list, required: true

  def keys_tab(assigns) do
    ~H"""
    <.key_management_card
      create_key_path={@create_key_path}
      csrf_token={@csrf_token}
      delete_key_path={@delete_key_path}
      generated_key={@generated_key}
      key_changeset={@key_changeset}
      keys={@keys}
      organization={@organization}
      organizations={[]}
      packages={@packages}
    />
    """
  end
end

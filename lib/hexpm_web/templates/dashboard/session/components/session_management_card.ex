defmodule HexpmWeb.Dashboard.Session.Components.SessionManagementCard do
  @moduledoc """
  Session management card component for the dashboard.
  Displays active sessions with revoke functionality.
  """
  use Phoenix.Component
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Badge
  import HexpmWeb.Components.Table
  import HexpmWeb.Components.Tooltip
  import HexpmWeb.Components.Modal, only: [show_modal: 1]
  import HexpmWeb.Dashboard.Session.Components.RevokeSessionModal
  alias HexpmWeb.ViewHelpers

  attr :sessions, :list, required: true
  attr :current_session_token, :string, required: true

  def session_management_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 rounded-lg shadow-sm border border-grey-200 dark:border-grey-700 p-8">
      <%!-- Header --%>
      <div class="mb-6">
        <h2 class="text-xl font-semibold text-grey-900 dark:text-white mb-2">Sessions</h2>
        <p class="text-sm text-grey-500 dark:text-grey-300">
          Active sessions for your account. This includes both browser sessions and authorized OAuth applications.
        </p>
      </div>

      <%= if @sessions == [] do %>
        <div class="text-center py-8 text-grey-500 dark:text-grey-300">
          <p>No active sessions found.</p>
        </div>
      <% else %>
        <.table>
          <:header>
            <th class="px-4 py-3 text-left text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
              Type
            </th>
            <th class="px-4 py-3 text-left text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
              Name
            </th>
            <th class="px-4 py-3 text-left text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
              Application
            </th>
            <th class="px-4 py-3 text-left text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
              Last Activity
            </th>
            <th class="px-4 py-3 text-right text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
              Actions
            </th>
          </:header>

          <:row :for={session <- @sessions}>
            <.session_row
              session={session}
              current_session_token={@current_session_token}
            />
          </:row>
        </.table>

        <%!-- Modals rendered outside the table to avoid invalid HTML inside <tbody> --%>
        <%= for session <- @sessions, not is_current_session?(session, @current_session_token) do %>
          <.revoke_session_modal session={session} />
        <% end %>
      <% end %>
    </div>
    """
  end

  defp session_row(assigns) do
    modal_id = "revoke-session-#{assigns.session.id}"

    # Check if this is the current session
    is_current = is_current_session?(assigns.session, assigns.current_session_token)

    assigns = assign(assigns, modal_id: modal_id, is_current: is_current)

    ~H"""
    <tr class="last:border-0 hover:bg-grey-50 dark:hover:bg-grey-700 transition-colors">
      <%!-- Type Column --%>
      <td class="px-4 py-4">
        <%= if @session.type == "browser" do %>
          <.badge variant="blue">Browser</.badge>
        <% else %>
          <.badge variant="green">OAuth</.badge>
        <% end %>
        <%= if @is_current do %>
          <.badge variant="default">Current</.badge>
        <% end %>
      </td>

      <%!-- Name Column --%>
      <td class="px-4 py-4">
        <span class="text-grey-900 dark:text-white">
          {@session.name || "Unnamed session"}
        </span>
      </td>

      <%!-- Application Column --%>
      <td class="px-4 py-4">
        <%= if @session.type == "oauth" and @session.client do %>
          <span class="text-grey-900 dark:text-white">{@session.client.name}</span>
        <% else %>
          <span class="text-grey-500 dark:text-grey-300">-</span>
        <% end %>
      </td>

      <%!-- Last Activity Column --%>
      <td class="px-4 py-4">
        <%= if @session.last_use && @session.last_use.used_at do %>
          <.tooltip text={"#{ViewHelpers.pretty_datetime(@session.last_use.used_at)}\n#{@session.last_use.ip}\n#{@session.last_use.user_agent}"}>
            <span class="text-grey-700 dark:text-grey-200 cursor-help border-b border-dashed border-grey-400 dark:border-grey-500">
              {ViewHelpers.pretty_date(@session.last_use.used_at)}
            </span>
          </.tooltip>
        <% else %>
          <span class="text-grey-700 dark:text-grey-200">
            {ViewHelpers.pretty_date(@session.inserted_at)}
          </span>
        <% end %>
      </td>

      <%!-- Actions Column --%>
      <td class="px-4 py-4">
        <div class="flex items-center justify-end gap-1">
          <%= if @is_current do %>
            <.tooltip text="Cannot revoke current session">
              <.icon_button icon="trash" variant="default" disabled />
            </.tooltip>
          <% else %>
            <.tooltip text="Revoke session">
              <.icon_button
                icon="trash"
                variant="danger"
                phx-click={show_modal(@modal_id)}
                aria-label="Revoke session"
              />
            </.tooltip>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end

  defp is_current_session?(session, current_session_token) do
    session.type == "browser" && current_session_token &&
      case Base.decode64(current_session_token) do
        {:ok, token} -> Plug.Crypto.secure_compare(token, session.session_token)
        _ -> false
      end
  end
end

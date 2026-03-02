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
    <div class="tw:bg-white tw:rounded-lg tw:shadow-sm tw:border tw:border-grey-200 tw:p-8">
      <%!-- Header --%>
      <div class="tw:mb-6">
        <h2 class="tw:text-xl tw:font-semibold tw:mb-2">Sessions</h2>
        <p class="tw:text-sm tw:text-grey-500">
          Active sessions for your account. This includes both browser sessions and authorized OAuth applications.
        </p>
      </div>

      <%= if @sessions == [] do %>
        <div class="tw:text-center tw:py-8 tw:text-grey-500">
          <p>No active sessions found.</p>
        </div>
      <% else %>
        <.table>
          <:header>
            <th class="tw:px-4 tw:py-3 tw:text-left tw:text-small tw:font-medium tw:text-grey-700">
              Type
            </th>
            <th class="tw:px-4 tw:py-3 tw:text-left tw:text-small tw:font-medium tw:text-grey-700">
              Name
            </th>
            <th class="tw:px-4 tw:py-3 tw:text-left tw:text-small tw:font-medium tw:text-grey-700">
              Application
            </th>
            <th class="tw:px-4 tw:py-3 tw:text-left tw:text-small tw:font-medium tw:text-grey-700">
              Last Activity
            </th>
            <th class="tw:px-4 tw:py-3 tw:text-right tw:text-small tw:font-medium tw:text-grey-700">
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
    <tr class="last:tw:border-0 tw:hover:bg-grey-50 tw:transition-colors">
      <%!-- Type Column --%>
      <td class="tw:px-4 tw:py-4">
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
      <td class="tw:px-4 tw:py-4">
        <span class="tw:text-grey-900">
          {@session.name || "Unnamed session"}
        </span>
      </td>

      <%!-- Application Column --%>
      <td class="tw:px-4 tw:py-4">
        <%= if @session.type == "oauth" and @session.client do %>
          <span class="tw:text-grey-900">{@session.client.name}</span>
        <% else %>
          <span class="tw:text-grey-500">-</span>
        <% end %>
      </td>

      <%!-- Last Activity Column --%>
      <td class="tw:px-4 tw:py-4">
        <%= if @session.last_use && @session.last_use.used_at do %>
          <.tooltip text={"#{ViewHelpers.pretty_datetime(@session.last_use.used_at)} • IP: #{@session.last_use.ip}"}>
            <span class="tw:text-grey-700 tw:cursor-help tw:border-b tw:border-dashed tw:border-grey-400">
              {ViewHelpers.pretty_date(@session.last_use.used_at)}
            </span>
          </.tooltip>
        <% else %>
          <span class="tw:text-grey-700">
            {ViewHelpers.pretty_date(@session.inserted_at)}
          </span>
        <% end %>
      </td>

      <%!-- Actions Column --%>
      <td class="tw:px-4 tw:py-4">
        <div class="tw:flex tw:items-center tw:justify-end tw:gap-1">
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

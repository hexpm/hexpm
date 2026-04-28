defmodule HexpmWeb.Dashboard.Email.Components.EmailManagementCard do
  @moduledoc """
  Email management card component for the dashboard.
  Displays all user emails with actions and add email form.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Badge
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Table
  import HexpmWeb.Components.Tooltip
  import HexpmWeb.Components.Modal, only: [show_modal: 1]
  import HexpmWeb.Dashboard.Email.Components.AddEmailModal
  import HexpmWeb.Dashboard.Email.Components.DeleteEmailModal
  import HexpmWeb.ViewIcons, only: [icon: 3]

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  attr :emails, :list, required: true
  attr :create_changeset, :any, required: true
  attr :current_user, :map, required: true

  def email_management_card(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-8">
      <%!-- Title --%>
      <h2 class="text-grey-900 dark:text-white text-xl font-semibold mb-2">
        Email Settings
      </h2>

      <%!-- Info Text --%>
      <p class="text-sm text-grey-500 dark:text-grey-300 mb-6">
        The <strong class="font-semibold">primary</strong>
        email address will be used when Hex.pm communicates with you.
        The <strong class="font-semibold">public</strong>
        email address will be displayed on your profile page.
      </p>

      <%!-- Email Table --%>
      <.table>
        <:header>
          <th class="px-0 py-3 text-left text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
            Email
          </th>
          <th class="px-4 py-3 text-left text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
            Status
          </th>
          <th class="px-4 py-3 text-right text-xs font-semibold text-grey-500 dark:text-grey-300 uppercase tracking-wider">
            Actions
          </th>
        </:header>
        <:row :for={email <- @emails}>
          <.email_row email={email} current_user={@current_user} />
        </:row>
      </.table>

      <%!-- Delete Email Modals rendered outside the table to avoid invalid HTML inside <tbody> --%>
      <%= for email <- @emails do %>
        <.delete_email_modal email={email} current_user={@current_user} />
      <% end %>

      <%!-- Add Email Button --%>
      <div>
        <.button
          variant="outline"
          size="md"
          phx-click={show_modal("add-email-modal")}
          id="add-email-button"
          class="border-dashed"
        >
          <span class="flex items-center gap-1">
            {icon(:heroicon, "plus", width: 14, height: 14)}
            <span>Add New Email</span>
          </span>
        </.button>
      </div>
    </div>

    <%!-- Add Email Modal --%>
    <.add_email_modal changeset={@create_changeset} current_user={@current_user} />
    """
  end

  attr :email, :map, required: true
  attr :current_user, :map, required: true

  defp email_row(assigns) do
    modal_id = "delete-email-#{assigns.email.id}"
    assigns = assign(assigns, :modal_id, modal_id)

    ~H"""
    <tr>
      <%!-- Email Column --%>
      <td class="px-0 py-4">
        <span class="text-base font-medium text-grey-800 dark:text-white break-all">
          {@email.email}
        </span>
      </td>

      <%!-- Status Column --%>
      <td class="px-4 py-4">
        <div class="flex flex-wrap gap-2">
          <.badge :if={not @email.verified}>Not Verified</.badge>
          <.badge :if={@email.primary}>Primary</.badge>
          <.badge :if={@email.public}>Public</.badge>
          <.badge :if={@email.verified and not @email.public}>Private</.badge>
          <.badge :if={@email.gravatar}>Gravatar</.badge>
        </div>
      </td>

      <%!-- Actions Column --%>
      <td class="px-4 py-4">
        <div class="flex items-center justify-end gap-1">
          <%!-- Set as Primary --%>
          <%= if @email.verified and not @email.primary do %>
            <.sudo_form
              current_user={@current_user}
              action={~p"/dashboard/email/primary"}
              class="inline-flex items-center m-0"
            >
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Set as primary">
                <.icon_button type="submit" icon="star" variant="default" aria-label="Set as primary" />
              </.tooltip>
            </.sudo_form>
          <% end %>

          <%!-- Set as Public / Private --%>
          <%= if @email.verified and not @email.public do %>
            <.sudo_form
              current_user={@current_user}
              action={~p"/dashboard/email/public"}
              class="inline-flex items-center m-0"
            >
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Set as public">
                <.icon_button
                  type="submit"
                  icon="globe-alt"
                  variant="default"
                  aria-label="Set as public"
                />
              </.tooltip>
            </.sudo_form>
          <% end %>

          <%= if @email.verified and @email.public do %>
            <.sudo_form
              current_user={@current_user}
              action={~p"/dashboard/email/public"}
              class="inline-flex items-center m-0"
            >
              <input type="hidden" name="email" value="none" />
              <.tooltip text="Set as private">
                <.icon_button
                  type="submit"
                  icon="lock-closed"
                  variant="default"
                  aria-label="Set as private"
                />
              </.tooltip>
            </.sudo_form>
          <% end %>

          <%!-- Set as Gravatar / Unset Gravatar --%>
          <%= if @email.verified and not @email.gravatar do %>
            <.sudo_form
              current_user={@current_user}
              action={~p"/dashboard/email/gravatar"}
              class="inline-flex items-center m-0"
            >
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Set as gravatar">
                <.icon_button
                  type="submit"
                  icon="user-circle"
                  variant="default"
                  aria-label="Set as gravatar"
                />
              </.tooltip>
            </.sudo_form>
          <% end %>

          <%= if @email.verified and @email.gravatar do %>
            <.sudo_form
              current_user={@current_user}
              action={~p"/dashboard/email/gravatar"}
              class="inline-flex items-center m-0"
            >
              <input type="hidden" name="email" value="none" />
              <.tooltip text="Unset gravatar">
                <.icon_button
                  type="submit"
                  icon="user-circle"
                  variant="default"
                  aria-label="Unset gravatar"
                />
              </.tooltip>
            </.sudo_form>
          <% end %>

          <%!-- Resend Verification --%>
          <%= unless @email.verified do %>
            <.sudo_form
              current_user={@current_user}
              action={~p"/dashboard/email/resend"}
              class="inline-flex items-center m-0"
            >
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Resend verification email">
                <.icon_button
                  type="submit"
                  icon="envelope"
                  variant="default"
                  aria-label="Resend verification"
                />
              </.tooltip>
            </.sudo_form>
          <% end %>

          <%!-- Delete Button --%>
          <.tooltip text="Delete email" class="inline-block">
            <.icon_button
              icon="trash"
              variant="danger"
              phx-click={show_modal(@modal_id)}
              aria-label="Delete email"
            />
          </.tooltip>
        </div>
      </td>
    </tr>
    """
  end
end

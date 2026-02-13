defmodule HexpmWeb.Dashboard.Email.Components.EmailManagementCard do
  @moduledoc """
  Email management card component for the dashboard.
  Displays all user emails with actions and add email form.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Badge
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
  attr :csrf_token, :string, required: true

  def email_management_card(assigns) do
    ~H"""
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-8">
      <%!-- Title --%>
      <h2 class="tw:text-grey-900 tw:text-xl tw:font-semibold tw:mb-2">
        Email Settings
      </h2>

      <%!-- Info Text --%>
      <p class="tw:text-sm tw:text-grey-500 tw:mb-6">
        The <strong class="tw:font-semibold">primary</strong>
        email address will be used when Hex.pm communicates with you.
        The <strong class="tw:font-semibold">public</strong>
        email address will be displayed on your profile page.
      </p>

      <%!-- Email Table --%>
      <div class="tw:border-b tw:border-grey-200 tw:mb-6">
        <table class="tw:w-full">
          <thead>
            <tr class="tw:border-b tw:border-grey-200">
              <th class="tw:px-0 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
                Email
              </th>
              <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">
                Status
              </th>
              <th class="tw:px-4 tw:py-3 tw:text-right tw:text-sm tw:font-medium tw:text-grey-500">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="tw:divide-y tw:divide-grey-200">
            <.email_row :for={email <- @emails} email={email} csrf_token={@csrf_token} />
          </tbody>
        </table>
      </div>

      <%!-- Add Email Button --%>
      <div>
        <.button
          variant="outline"
          size="md"
          phx-click={show_modal("add-email-modal")}
          id="add-email-button"
          class="tw:border-dashed"
        >
          <span class="tw:flex tw:items-center tw:gap-1">
            {icon(:heroicon, "plus", width: 14, height: 14)}
            <span>Add New Email</span>
          </span>
        </.button>
      </div>
    </div>

    <%!-- Add Email Modal --%>
    <.add_email_modal changeset={@create_changeset} />
    """
  end

  attr :email, :map, required: true
  attr :csrf_token, :string, required: true

  defp email_row(assigns) do
    modal_id = "delete-email-#{String.replace(assigns.email.email, ~r/[^a-zA-Z0-9]/, "-")}"
    assigns = assign(assigns, :modal_id, modal_id)

    ~H"""
    <tr>
      <%!-- Email Column --%>
      <td class="tw:px-0 tw:py-4">
        <span class="tw:text-base tw:font-medium tw:text-grey-800 tw:break-all">
          {@email.email}
        </span>
      </td>

      <%!-- Status Column --%>
      <td class="tw:px-4 tw:py-4">
        <div class="tw:flex tw:flex-wrap tw:gap-2">
          <.badge :if={not @email.verified}>Not Verified</.badge>
          <.badge :if={@email.primary}>Primary</.badge>
          <.badge :if={@email.public}>Public</.badge>
          <.badge :if={@email.verified and not @email.public}>Private</.badge>
          <.badge :if={@email.gravatar}>Gravatar</.badge>
        </div>
      </td>

      <%!-- Actions Column --%>
      <td class="tw:px-4 tw:py-4">
        <div class="tw:flex tw:items-center tw:justify-end tw:gap-1">
          <%!-- Set as Primary --%>
          <%= if @email.verified and not @email.primary do %>
            <form
              action={~p"/dashboard/email/primary"}
              method="post"
              class="tw:inline-flex tw:items-center tw:m-0"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Set as primary">
                <.icon_button type="submit" icon="star" variant="default" aria-label="Set as primary" />
              </.tooltip>
            </form>
          <% end %>

          <%!-- Set as Public / Private --%>
          <%= if @email.verified and not @email.public do %>
            <form
              action={~p"/dashboard/email/public"}
              method="post"
              class="tw:inline-flex tw:items-center tw:m-0"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Set as public">
                <.icon_button
                  type="submit"
                  icon="globe-alt"
                  variant="default"
                  aria-label="Set as public"
                />
              </.tooltip>
            </form>
          <% end %>

          <%= if @email.verified and @email.public do %>
            <form
              action={~p"/dashboard/email/public"}
              method="post"
              class="tw:inline-flex tw:items-center tw:m-0"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="email" value="none" />
              <.tooltip text="Set as private">
                <.icon_button
                  type="submit"
                  icon="lock-closed"
                  variant="default"
                  aria-label="Set as private"
                />
              </.tooltip>
            </form>
          <% end %>

          <%!-- Set as Gravatar / Unset Gravatar --%>
          <%= if @email.verified and not @email.gravatar do %>
            <form
              action={~p"/dashboard/email/gravatar"}
              method="post"
              class="tw:inline-flex tw:items-center tw:m-0"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Set as gravatar">
                <.icon_button
                  type="submit"
                  icon="user-circle"
                  variant="default"
                  aria-label="Set as gravatar"
                />
              </.tooltip>
            </form>
          <% end %>

          <%= if @email.verified and @email.gravatar do %>
            <form
              action={~p"/dashboard/email/gravatar"}
              method="post"
              class="tw:inline-flex tw:items-center tw:m-0"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="email" value="none" />
              <.tooltip text="Unset gravatar">
                <.icon_button
                  type="submit"
                  icon="user-circle"
                  variant="default"
                  aria-label="Unset gravatar"
                  class="tw:opacity-50"
                />
              </.tooltip>
            </form>
          <% end %>

          <%!-- Resend Verification --%>
          <%= unless @email.verified do %>
            <form
              action={~p"/dashboard/email/resend"}
              method="post"
              class="tw:inline-flex tw:items-center tw:m-0"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="email" value={@email.email} />
              <.tooltip text="Resend verification email">
                <.icon_button
                  type="submit"
                  icon="envelope"
                  variant="default"
                  aria-label="Resend verification"
                />
              </.tooltip>
            </form>
          <% end %>

          <%!-- Delete Button --%>
          <.tooltip text="Delete email" class="tw:inline-block">
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

    <%!-- Delete Email Modal --%>
    <.delete_email_modal email={@email} csrf_token={@csrf_token} />
    """
  end
end

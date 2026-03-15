defmodule HexpmWeb.Dashboard.AuditLog.Components.AuditLogCard do
  @moduledoc """
  Recent activities card component for the dashboard.
  Displays a timeline of audit log events grouped by time period.
  """
  use Phoenix.Component
  import HexpmWeb.ViewIcons, only: [icon: 3]
  alias HexpmWeb.ViewHelpers
  alias Hexpm.Accounts.AuditLog

  attr :audit_logs, :list, required: true

  def audit_log_card(assigns) do
    grouped = group_by_period(assigns.audit_logs)
    assigns = assign(assigns, :grouped, grouped)

    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-grey-200 p-8">
      <%!-- Header --%>
      <div class="mb-8">
        <h2 class="text-xl font-semibold mb-2">Recent Activities</h2>
        <p class="text-sm text-grey-500">
          A log of recent actions taken on your account.
        </p>
      </div>

      <%= if @audit_logs == [] do %>
        <div class="text-center py-12 text-grey-500">
          <span class="flex justify-center mb-3 text-grey-300">
            {icon(:heroicon, "clock", width: 40, height: 40)}
          </span>
          <p>No recent activities found.</p>
        </div>
      <% else %>
        <div class="space-y-8">
          <%= for {period_label, entries} <- @grouped do %>
            <.period_group period_label={period_label} entries={entries} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :period_label, :string, required: true
  attr :entries, :list, required: true

  defp period_group(assigns) do
    assigns = assign(assigns, :last_idx, length(assigns.entries) - 1)

    ~H"""
    <div>
      <%!-- Period label e.g. "THIS WEEK" / "EARLIER THIS MONTH" --%>
      <p class="text-xs font-semibold tracking-wider uppercase text-grey-400 mb-4">
        {@period_label}
      </p>

      <div class="relative">
        <%= for {log, idx} <- Enum.with_index(@entries) do %>
          <.timeline_item log={log} is_last={idx == @last_idx} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :log, :map, required: true
  attr :is_last, :boolean, default: false

  defp timeline_item(assigns) do
    icon = icon_for_action(assigns.log.action)
    description = humanize_action(assigns.log)
    assigns = assign(assigns, icon: icon, description: description)

    ~H"""
    <div class="flex gap-4 group">
      <%!-- Left column: dot + connector line --%>
      <div class="flex flex-col items-center flex-shrink-0">
        <%!-- Circle dot --%>
        <div class="w-8 h-8 rounded-full border-2 border-grey-200 bg-white flex items-center justify-center z-10 text-grey-400">
          {icon(:heroicon, @icon, width: 16, height: 16)}
        </div>
        <%!-- Vertical connector line (hidden on last item) --%>
        <%= unless @is_last do %>
          <div class="w-px flex-1 bg-grey-200 my-1 min-h-[20px]"></div>
        <% end %>
      </div>

      <%!-- Right column: action text + date --%>
      <div class="pb-6 flex-1 min-w-0">
        <p class="text-base font-medium text-grey-700 leading-6">
          {@description}
        </p>
        <p
          class="text-xs font-medium text-grey-500 mt-0.5"
          title={ViewHelpers.pretty_datetime(@log.inserted_at)}
        >
          {ViewHelpers.pretty_date(@log.inserted_at, :short)}
        </p>
      </div>
    </div>
    """
  end

  # Groups audit logs into time periods: "This Week", "Earlier This Month",
  # "Last Month", and per-month buckets for older entries.
  # Returns an ordered list of {label, entries} tuples.
  defp group_by_period(audit_logs) do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)
    start_of_week = Date.add(today, -Date.day_of_week(today) + 1)
    start_of_month = Date.new!(today.year, today.month, 1)

    last_month_end = Date.add(start_of_month, -1)
    start_of_last_month = Date.new!(last_month_end.year, last_month_end.month, 1)

    grouped =
      Enum.group_by(audit_logs, fn log ->
        log_date = DateTime.to_date(log.inserted_at)

        cond do
          Date.compare(log_date, start_of_week) != :lt -> :this_week
          Date.compare(log_date, start_of_month) != :lt -> :earlier_this_month
          Date.compare(log_date, start_of_last_month) != :lt -> :last_month
          true -> {log_date.year, log_date.month}
        end
      end)

    order = [:this_week, :earlier_this_month, :last_month]

    ordered_keys =
      (order ++
         (grouped
          |> Map.keys()
          |> Enum.filter(&is_tuple/1)
          |> Enum.sort(:desc)))
      |> Enum.filter(&Map.has_key?(grouped, &1))

    Enum.map(ordered_keys, fn key ->
      {period_label(key), Map.get(grouped, key, [])}
    end)
  end

  defp period_label(:this_week), do: "This Week"
  defp period_label(:earlier_this_month), do: "Earlier This Month"
  defp period_label(:last_month), do: "Last Month"

  defp period_label({year, month}) do
    month_name =
      ~w(January February March April May June July August September October November December)
      |> Enum.at(month - 1)

    "#{month_name} #{year}"
  end

  defp icon_for_action("key." <> _), do: "key"
  defp icon_for_action("email." <> _), do: "envelope"
  defp icon_for_action("security." <> _), do: "shield-check"
  defp icon_for_action("password." <> _), do: "lock-closed"
  defp icon_for_action("session." <> _), do: "computer-desktop"
  defp icon_for_action("organization." <> _), do: "building-office"
  defp icon_for_action("release." <> _), do: "cube"
  defp icon_for_action("docs." <> _), do: "document-text"
  defp icon_for_action("owner." <> _), do: "user-group"
  defp icon_for_action("billing." <> _), do: "credit-card"
  defp icon_for_action("user." <> _), do: "user"
  defp icon_for_action(_), do: "clock"

  defp humanize_action(%AuditLog{
         action: "docs.publish",
         params: %{"package" => %{"name" => pkg}, "release" => %{"version" => vsn}}
       }) do
    "Published documentation for #{pkg} (#{vsn})"
  end

  defp humanize_action(%AuditLog{
         action: "docs.revert",
         params: %{"package" => %{"name" => pkg}, "release" => %{"version" => vsn}}
       }) do
    "Reverted documentation for #{pkg} (#{vsn})"
  end

  defp humanize_action(%AuditLog{action: "key.generate", params: %{"name" => name}}) do
    "Generated key: #{name}"
  end

  defp humanize_action(%AuditLog{action: "key.remove", params: %{"name" => name}}) do
    "Removed key: #{name}"
  end

  defp humanize_action(%AuditLog{
         action: "owner.add",
         params: %{"user" => %{"username" => username}, "package" => %{"name" => pkg}}
       }) do
    "Added #{username} as owner of #{pkg}"
  end

  defp humanize_action(%AuditLog{
         action: "owner.transfer",
         params: %{"package" => %{"name" => pkg}, "user" => %{"username" => username}}
       }) do
    "Transferred #{pkg} to #{username}"
  end

  defp humanize_action(%AuditLog{
         action: "owner.remove",
         params: %{"user" => %{"username" => username}, "package" => %{"name" => pkg}}
       }) do
    "Removed #{username} from owners of #{pkg}"
  end

  defp humanize_action(%AuditLog{
         action: "release.publish",
         params: %{"package" => %{"name" => pkg}, "release" => %{"version" => vsn}}
       }) do
    "Published #{pkg} (#{vsn})"
  end

  defp humanize_action(%AuditLog{
         action: "release.revert",
         params: %{"package" => %{"name" => pkg}, "release" => %{"version" => vsn}}
       }) do
    "Reverted #{pkg} (#{vsn})"
  end

  defp humanize_action(%AuditLog{
         action: "release.retire",
         params: %{"package" => %{"name" => pkg}, "release" => %{"version" => vsn}}
       }) do
    "Retired #{pkg} (#{vsn})"
  end

  defp humanize_action(%AuditLog{
         action: "release.unretire",
         params: %{"package" => %{"name" => pkg}, "release" => %{"version" => vsn}}
       }) do
    "Unretired #{pkg} (#{vsn})"
  end

  defp humanize_action(%AuditLog{action: "email.add", params: %{"email" => email}}) do
    "Added email #{email}"
  end

  defp humanize_action(%AuditLog{action: "email.remove", params: %{"email" => email}}) do
    "Removed email #{email}"
  end

  defp humanize_action(%AuditLog{
         action: "email.primary",
         params: %{"new_email" => %{"email" => email}}
       }) do
    "Set #{email} as primary email"
  end

  defp humanize_action(%AuditLog{
         action: "email.public",
         params: %{"old_email" => %{"email" => email}, "new_email" => nil}
       }) do
    "Set #{email} as private email"
  end

  defp humanize_action(%AuditLog{
         action: "email.public",
         params: %{"new_email" => %{"email" => email}}
       }) do
    "Set #{email} as public email"
  end

  defp humanize_action(%AuditLog{
         action: "email.gravatar",
         params: %{"new_email" => %{"email" => email}}
       }) do
    "Set #{email} as gravatar email"
  end

  defp humanize_action(%AuditLog{action: "user.create"}) do
    "Created user account"
  end

  defp humanize_action(%AuditLog{action: "user.update"}) do
    "Updated user profile"
  end

  defp humanize_action(%AuditLog{action: "security.update"}) do
    "Updated TFA settings"
  end

  defp humanize_action(%AuditLog{action: "security.rotate_recovery_codes"}) do
    "Rotated TFA recovery codes"
  end

  defp humanize_action(%AuditLog{action: "organization.create", params: %{"name" => name}}) do
    "Created organization #{name}"
  end

  defp humanize_action(%AuditLog{
         action: "organization.member.add",
         params: %{"user" => %{"username" => username}, "organization" => %{"name" => org}}
       }) do
    "Added #{username} to #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "organization.member.remove",
         params: %{"user" => %{"username" => username}, "organization" => %{"name" => org}}
       }) do
    "Removed #{username} from #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "organization.member.role",
         params: %{
           "user" => %{"username" => username},
           "role" => role,
           "organization" => %{"name" => org}
         }
       }) do
    "Changed #{username}'s role to #{role} in #{org}"
  end

  defp humanize_action(%AuditLog{action: "password.reset.init"}) do
    "Requested a password reset"
  end

  defp humanize_action(%AuditLog{action: "password.reset.finish"}) do
    "Reset password successfully"
  end

  defp humanize_action(%AuditLog{action: "password.update"}) do
    "Updated password"
  end

  defp humanize_action(%AuditLog{action: "password.add"}) do
    "Added password"
  end

  defp humanize_action(%AuditLog{action: "password.remove"}) do
    "Removed password"
  end

  defp humanize_action(%AuditLog{
         action: "billing.checkout",
         params: %{"organization" => %{"name" => org}}
       }) do
    "Updated payment method for #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "billing.cancel",
         params: %{"organization" => %{"name" => org}}
       }) do
    "Cancelled billing for #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "billing.resume",
         params: %{"organization" => %{"name" => org}}
       }) do
    "Resumed billing for #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "billing.create",
         params: %{"organization" => %{"name" => org}}
       }) do
    "Added billing information for #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "billing.update",
         params: %{"organization" => %{"name" => org}}
       }) do
    "Updated billing information for #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "billing.change_plan",
         params: %{"organization" => %{"name" => org}, "plan_id" => plan_id}
       }) do
    plan = if plan_id == "organization-monthly", do: "monthly", else: "annual"
    "Changed billing plan for #{org} to #{plan}"
  end

  defp humanize_action(%AuditLog{
         action: "billing.pay_invoice",
         params: %{"organization" => %{"name" => org}}
       }) do
    "Paid invoice for #{org}"
  end

  defp humanize_action(%AuditLog{
         action: "session.create",
         params: %{"type" => "browser", "name" => name}
       }) do
    "Logged in from #{name}"
  end

  defp humanize_action(%AuditLog{
         action: "session.create",
         params: %{
           "type" => "oauth",
           "client" => %{"name" => client_name},
           "name" => session_name
         }
       })
       when is_binary(session_name) do
    "Authorized OAuth application: #{client_name} (#{session_name})"
  end

  defp humanize_action(%AuditLog{
         action: "session.create",
         params: %{"type" => "oauth", "client" => %{"name" => client_name}}
       }) do
    "Authorized OAuth application: #{client_name}"
  end

  defp humanize_action(%AuditLog{
         action: "session.revoke",
         params: %{"type" => "browser", "name" => name}
       }) do
    "Logged out from #{name}"
  end

  defp humanize_action(%AuditLog{
         action: "session.revoke",
         params: %{
           "type" => "oauth",
           "client" => %{"name" => client_name},
           "name" => session_name
         }
       })
       when is_binary(session_name) do
    "Revoked OAuth application: #{client_name} (#{session_name})"
  end

  defp humanize_action(%AuditLog{
         action: "session.revoke",
         params: %{"type" => "oauth", "client" => %{"name" => client_name}}
       }) do
    "Revoked OAuth application: #{client_name}"
  end

  defp humanize_action(%AuditLog{
         action: "user_provider.create",
         params: %{"provider" => provider}
       }) do
    "Connected #{provider} account"
  end

  defp humanize_action(%AuditLog{
         action: "user_provider.delete",
         params: %{"provider" => provider}
       }) do
    "Disconnected #{provider} account"
  end

  defp humanize_action(%AuditLog{action: action}) do
    action
    |> String.replace(".", " ")
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end

defmodule HexpmWeb.Dashboard.Organization.Components.BillingTab do
  use Phoenix.Component

  import HexpmWeb.Dashboard.Organization.Components.BillingSubscription,
    only: [billing_subscription: 1]

  import HexpmWeb.Dashboard.Organization.Components.BillingInfoForms,
    only: [billing_info_forms: 1]

  import HexpmWeb.Dashboard.Organization.Components.BillingInvoices,
    only: [billing_invoices: 1]

  alias HexpmWeb.Dashboard.Organization.Components.BillingHelpers

  attr :organization, :map, required: true
  attr :current_user, :map, required: true
  attr :billing_started?, :boolean, default: false
  attr :billing_email, :string, default: nil
  attr :plan_id, :string, default: nil
  attr :quantity, :integer, default: nil
  attr :max_period_quantity, :integer, default: nil
  attr :subscription, :map, default: nil
  attr :card, :map, default: nil
  attr :discount, :map, default: nil
  attr :tax_rate, :any, default: nil
  attr :amount_with_tax, :integer, default: nil
  attr :proration_amount, :integer, default: 0
  attr :proration_days, :integer, default: 0
  attr :checkout_html, :string, default: nil
  attr :post_action, :string, default: nil
  attr :csrf_token, :string, default: nil
  attr :invoices, :list, default: []
  attr :person, :map, default: nil
  attr :company, :map, default: nil
  attr :params, :map, default: %{}
  attr :errors, :map, default: %{}
  attr :script_src_nonce, :string, default: ""
  attr :stripe_publishable_key, :string, default: nil

  def billing_tab(assigns) do
    assigns =
      assigns
      |> assign(:member_count, length(assigns.organization.organization_users || []))

    ~H"""
    <div class="space-y-6">
      <%= if @billing_started? do %>
        <.billing_subscription
          current_user={@current_user}
          organization={@organization}
          plan_id={@plan_id}
          quantity={@quantity}
          member_count={@member_count}
          subscription={@subscription}
          card={@card}
          discount={@discount}
          tax_rate={@tax_rate}
          amount_with_tax={@amount_with_tax}
          checkout_html={@checkout_html}
          post_action={@post_action}
          csrf_token={@csrf_token}
          proration_amount={@proration_amount}
          proration_days={@proration_days}
          max_period_quantity={@max_period_quantity}
          script_src_nonce={@script_src_nonce}
          stripe_publishable_key={@stripe_publishable_key}
        />
      <% else %>
        <.setup_billing_notice organization={@organization} />
      <% end %>

      <.billing_info_forms
        organization={@organization}
        current_user={@current_user}
        billing_started?={@billing_started?}
        billing_email={@billing_email}
        person={@person}
        company={@company}
        params={@params}
        errors={@errors}
      />

      <.billing_invoices
        current_user={@current_user}
        organization={@organization}
        invoices={@invoices}
        card={@card}
        subscription={@subscription}
        stripe_publishable_key={@stripe_publishable_key}
      />
    </div>
    """
  end

  defp setup_billing_notice(assigns) do
    ~H"""
    <div class="bg-amber-50 border border-amber-200 rounded-lg px-6 py-5">
      <%= if Hexpm.Accounts.Organization.trialing?(@organization) do %>
        <h2 class="text-amber-900 text-base font-semibold mb-2">Trial active</h2>
        <p class="text-sm text-amber-800 mb-1">
          Subscription is in trial mode until {HexpmWeb.ViewHelpers.pretty_date(
            @organization.trial_end
          )}.
          After the trial is over private packages will not be available.
        </p>
        <p class="text-sm text-amber-800">
          Add a payment method to continue using organizations after the trial.
          Subscription cost is <strong>$7.00 per user / month</strong> + local VAT when applicable.
          Enter your billing information below to enable the payment method form.
        </p>
      <% else %>
        <h2 class="text-amber-900 text-base font-semibold mb-2">Subscription not active</h2>
        <p class="text-sm text-amber-800 mb-1">
          Private packages will not be available until a payment method has been added.
        </p>
        <p class="text-sm text-amber-800">
          Subscription cost is <strong>$7.00 per user / month</strong> + local VAT when applicable.
          Enter your billing information below to enable the payment method form.
        </p>
      <% end %>
    </div>
    """
  end

  def payment_date(iso_string), do: BillingHelpers.payment_date(iso_string)
end

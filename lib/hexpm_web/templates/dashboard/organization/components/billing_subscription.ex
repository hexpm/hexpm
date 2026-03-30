defmodule HexpmWeb.Dashboard.Organization.Components.BillingSubscription do
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import Phoenix.HTML, only: [raw: 1]
  import HexpmWeb.Components.Modal, only: [modal: 1, show_modal: 1, hide_modal: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1]

  alias HexpmWeb.Dashboard.Organization.Components.BillingHelpers

  attr :organization, :map, required: true
  attr :plan_id, :string, default: nil
  attr :quantity, :integer, default: nil
  attr :member_count, :integer, default: 0
  attr :subscription, :map, default: nil
  attr :card, :map, default: nil
  attr :discount, :map, default: nil
  attr :tax_rate, :any, default: nil
  attr :amount_with_tax, :integer, default: nil
  attr :checkout_html, :string, default: nil
  attr :post_action, :string, default: nil
  attr :csrf_token, :string, default: nil
  attr :proration_amount, :integer, default: 0
  attr :proration_days, :integer, default: 0
  attr :max_period_quantity, :integer, default: nil
  attr :script_src_nonce, :string, default: ""
  attr :stripe_publishable_key, :string, default: nil

  def billing_subscription(assigns) do
    assigns = assign(assigns, :safe_quantity, assigns.quantity || 0)

    ~H"""
    <div class="bg-white border border-grey-200 rounded-lg overflow-hidden">
      <div class="px-6 py-5 border-b border-grey-200 flex items-center justify-between">
        <h2 class="text-grey-900 text-lg font-semibold">Subscription</h2>
        <%= if @subscription do %>
          <span class={[
            "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
            subscription_badge_class(@subscription)
          ]}>
            {BillingHelpers.subscription_badge_label(@subscription)}
            {BillingHelpers.discount_status(@discount)}
          </span>
        <% end %>
      </div>

      <div class="px-6 py-5">
        <%= if @subscription do %>
          <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <dt class="text-xs font-medium text-grey-500 uppercase tracking-wider mb-1">Plan</dt>
              <dd class="text-sm text-grey-900">
                <p>{BillingHelpers.plan(@plan_id)}</p>
                <div class="mt-2">
                  <.button
                    type="button"
                    variant="outline"
                    size="sm"
                    phx-click={show_modal("change-plan-modal")}
                  >
                    {if @plan_id == "organization-monthly",
                      do: "Switch to annual",
                      else: "Switch to monthly"}
                  </.button>
                </div>
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-grey-500 uppercase tracking-wider mb-1">
                Payment method
              </dt>
              <dd class="text-sm text-grey-900">{BillingHelpers.payment_card(@card)}</dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-grey-500 uppercase tracking-wider mb-1">
                Next invoice
              </dt>
              <dd class="text-sm text-grey-900">
                <%= if @subscription["cancel_at_period_end"] do %>
                  Subscription ends on {BillingHelpers.payment_date(
                    @subscription["current_period_end"]
                  )}
                <% else %>
                  {BillingHelpers.payment_date(@subscription["current_period_end"])}
                <% end %>
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-grey-500 uppercase tracking-wider mb-1">
                {if @plan_id == "organization-annually", do: "Annual cost", else: "Monthly cost"}
              </dt>
              <dd class="text-sm text-grey-900">
                {BillingHelpers.plan_price(@plan_id)} x {@safe_quantity} user(s)
                <%= if @tax_rate && @tax_rate != 0 do %>
                  x {@tax_rate}% VAT
                <% end %>
                = ${BillingHelpers.money(@amount_with_tax)}
              </dd>
            </div>
            <%= if BillingHelpers.subscription_status(@subscription, @card) not in ["Active", ""] do %>
              <div class="sm:col-span-2">
                <dt class="text-xs font-medium text-grey-500 uppercase tracking-wider mb-1">
                  Status
                </dt>
                <dd class="text-sm text-grey-900">
                  {BillingHelpers.subscription_status(@subscription, @card)}
                </dd>
              </div>
            <% end %>
            <div>
              <dt class="text-xs font-medium text-grey-500 uppercase tracking-wider mb-1">Seats</dt>
              <dd class="text-sm text-grey-900">
                <p>{@member_count} of {@safe_quantity} in use</p>
                <div class="mt-2 flex gap-2">
                  <.button
                    type="button"
                    variant="outline"
                    size="sm"
                    phx-click={show_modal("add-seats-modal")}
                  >
                    Add seats
                  </.button>
                  <.button
                    type="button"
                    variant="danger-outline"
                    size="sm"
                    phx-click={show_modal("remove-seats-modal")}
                  >
                    Remove seats
                  </.button>
                </div>
              </dd>
            </div>
          </dl>

          <script nonce={@script_src_nonce}>
            window.hexpm_billing_api_url = '/dashboard/billing-api';
            window.hexpm_billing_csrf_token = '<%= Plug.CSRFProtection.get_csrf_token() %>';
            window.hexpm_billing_success = function() { window.location.reload(); };
          </script>
          <div
            class="mt-6"
            id="billing-checkout-data"
            data-post-action={@post_action}
            data-csrf-token={@csrf_token}
          >
            {raw(@checkout_html || "")}
          </div>

          <div class="mt-4 flex gap-3 items-center">
            <%= if @subscription["cancel_at_period_end"] && @card && @card["brand"] do %>
              <form action={~p"/dashboard/orgs/#{@organization}/resume-billing"} method="post">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <button
                  type="submit"
                  class="inline-flex items-center justify-center gap-2 font-semibold rounded h-9 px-3 text-sm bg-green-600 text-white hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 cursor-pointer"
                >
                  Resume subscription
                </button>
              </form>
            <% end %>
            <.button
              type="button"
              variant="danger-outline"
              size="sm"
              disabled={!@subscription || @subscription["cancel_at_period_end"]}
              phx-click={show_modal("cancel-billing-modal")}
            >
              Cancel subscription
            </.button>
          </div>

          <.cancel_billing_modal organization={@organization} subscription={@subscription} />
          <.add_seats_modal
            organization={@organization}
            plan_id={@plan_id}
            quantity={@safe_quantity}
            member_count={@member_count}
            proration_amount={@proration_amount}
            proration_days={@proration_days}
            max_period_quantity={@max_period_quantity}
          />
          <.remove_seats_modal
            organization={@organization}
            quantity={@safe_quantity}
            member_count={@member_count}
            plan_id={@plan_id}
          />
          <.change_plan_modal organization={@organization} plan_id={@plan_id} />

          <%= if @stripe_publishable_key do %>
            <script nonce={@script_src_nonce}>
              (function() {
                var addSeatsForm = document.getElementById('add-seats-form');
                if (addSeatsForm) {
                  addSeatsForm.addEventListener('submit', async function(event) {
                    event.preventDefault();

                    var submitButton = addSeatsForm.querySelector('button[type="submit"]');
                    submitButton.disabled = true;
                    submitButton.textContent = 'Processing...';

                    try {
                      var formData = new URLSearchParams(new FormData(addSeatsForm));
                      var response = await fetch(addSeatsForm.action, {
                        method: 'POST',
                        body: formData,
                        credentials: 'same-origin',
                        redirect: 'manual'
                      });

                      if (response.type === 'opaqueredirect') {
                        window.location.reload();
                        return;
                      }

                      var data = await response.json();
                      submitButton.textContent = 'Authenticating payment...';

                      var stripe = Stripe(data.stripe_publishable_key);
                      var result = await stripe.confirmCardPayment(data.client_secret);

                      if (result.error) {
                        var voidData = new URLSearchParams();
                        voidData.append('invoice_id', data.invoice_id);
                        voidData.append('_csrf_token', formData.get('_csrf_token'));
                        await fetch('<%= ~p"/dashboard/orgs/#{@organization}/void-invoice" %>', {
                          method: 'POST',
                          body: voidData,
                          credentials: 'same-origin',
                          redirect: 'manual'
                        });
                        throw result.error;
                      }

                      submitButton.textContent = 'Payment confirmed! Adding seats...';
                      addSeatsForm.submit();
                    } catch (error) {
                      submitButton.textContent = error.message || 'Payment failed. Try again.';
                      submitButton.disabled = false;
                      setTimeout(function() { submitButton.textContent = 'Add seats'; }, 3000);
                    }
                  });
                }

                var scaButtons = document.querySelectorAll('.sca-pay-button');
                if (scaButtons.length > 0) {
                  var stripe = Stripe('<%= @stripe_publishable_key %>');

                  scaButtons.forEach(function(button) {
                    button.addEventListener('click', async function() {
                      var clientSecret = button.getAttribute('data-client-secret');
                      var paymentMethod = button.getAttribute('data-payment-method');
                      button.disabled = true;
                      button.textContent = 'Authenticating...';

                      try {
                        var confirmParams = {};
                        if (paymentMethod) {
                          confirmParams.payment_method = paymentMethod;
                        }
                        var result = await stripe.confirmCardPayment(clientSecret, confirmParams);
                        if (result.error) throw result.error;

                        button.textContent = 'Payment confirmed!';
                        setTimeout(function() { window.location.reload(); }, 2000);
                      } catch (error) {
                        button.textContent = error.message || 'Authentication failed. Try again.';
                        button.disabled = false;
                        setTimeout(function() { button.textContent = 'Authenticate payment'; }, 3000);
                      }
                    });
                  });
                }
              })();
            </script>
          <% end %>
        <% else %>
          <p class="text-sm text-grey-600 mb-4">
            No active subscription. <strong>Private packages will not be available</strong>
            until a payment method has been added.
          </p>
          <p class="text-sm text-grey-600 mb-6">
            Subscription cost is <strong>$7.00 per user / month</strong> + local VAT when applicable.
          </p>
          <script nonce={@script_src_nonce}>
            window.hexpm_billing_api_url = '/dashboard/billing-api';
            window.hexpm_billing_csrf_token = '<%= Plug.CSRFProtection.get_csrf_token() %>';
            window.hexpm_billing_success = function() { window.location.reload(); };
          </script>
          <div
            class="mt-4"
            id="billing-checkout-data"
            data-post-action={@post_action}
            data-csrf-token={@csrf_token}
          >
            {raw(@checkout_html || "")}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp subscription_badge_class(%{"status" => "active", "cancel_at_period_end" => false}),
    do: "bg-green-100 text-green-700"

  defp subscription_badge_class(%{"status" => "trialing"}),
    do: "bg-blue-100 text-blue-700"

  defp subscription_badge_class(%{"status" => "past_due"}),
    do: "bg-orange-100 text-orange-700"

  defp subscription_badge_class(_), do: "bg-grey-100 text-grey-600"

  attr :organization, :map, required: true
  attr :subscription, :map, default: nil

  defp cancel_billing_modal(assigns) do
    ~H"""
    <.modal id="cancel-billing-modal" title="Cancel subscription">
      <p class="text-sm text-grey-600 mb-2">
        Are you sure you want to cancel your subscription?
      </p>
      <p class="text-sm text-grey-600">
        Your subscription will remain active until the end of the current billing period.
        After that, private packages will no longer be accessible.
      </p>
      <form
        id="cancel-billing-form"
        action={~p"/dashboard/orgs/#{@organization}/cancel-billing"}
        method="post"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      </form>
      <:footer>
        <.button type="button" variant="secondary" phx-click={hide_modal("cancel-billing-modal")}>
          Keep subscription
        </.button>
        <.button
          type="submit"
          form="cancel-billing-form"
          variant="danger"
          onclick="this.disabled=true;this.form.submit();"
        >
          Yes, cancel
        </.button>
      </:footer>
    </.modal>
    """
  end

  attr :organization, :map, required: true
  attr :plan_id, :string, default: nil
  attr :quantity, :integer, default: 0
  attr :member_count, :integer, default: 0
  attr :proration_amount, :integer, default: 0
  attr :proration_days, :integer, default: 0
  attr :max_period_quantity, :integer, default: nil

  defp add_seats_modal(assigns) do
    ~H"""
    <.modal id="add-seats-modal" title="Add seats">
      <form id="add-seats-form" action={~p"/dashboard/orgs/#{@organization}/add-seats"} method="post">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input type="hidden" name="current-seats" value={@quantity} />
        <p class="text-sm text-grey-600 mb-4">
          You have {@quantity} seats of which {@member_count} are in use.
        </p>
        <div class="mb-4">
          <label for="add-seats-input" class="block text-sm font-medium text-grey-700 mb-1">
            Number of new seats to add
          </label>
          <div class="flex items-center gap-2">
            <input
              id="add-seats-input"
              type="number"
              name="add-seats"
              min="1"
              max="999"
              step="1"
              value="1"
              required
              class="w-24 h-10 px-3 border border-grey-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-purple-600"
            />
            <span class="text-sm text-grey-600">seat(s) @ {BillingHelpers.plan_price(@plan_id)}</span>
          </div>
        </div>
        <%= if @proration_amount && @proration_amount > 0 do %>
          <p class="text-sm text-grey-600">
            {BillingHelpers.proration_description(
              @plan_id,
              @proration_amount,
              @proration_days,
              @quantity,
              @max_period_quantity
            )}
          </p>
        <% end %>
      </form>
      <:footer>
        <.button type="button" variant="secondary" phx-click={hide_modal("add-seats-modal")}>
          Cancel
        </.button>
        <.button type="submit" form="add-seats-form" variant="primary">
          Add seats
        </.button>
      </:footer>
    </.modal>
    """
  end

  attr :organization, :map, required: true
  attr :quantity, :integer, default: 0
  attr :member_count, :integer, default: 0
  attr :plan_id, :string, default: nil

  defp remove_seats_modal(assigns) do
    ~H"""
    <.modal id="remove-seats-modal" title="Remove seats">
      <form
        id="remove-seats-form"
        action={~p"/dashboard/orgs/#{@organization}/remove-seats"}
        method="post"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <p class="text-sm text-grey-600 mb-4">
          You have {@quantity} seats of which {@member_count} are in use.
        </p>
        <%= if @quantity <= @member_count do %>
          <p class="text-sm font-medium text-red-600">
            You are already at the minimum number of seats. Remove members to free up seats.
          </p>
        <% else %>
          <div>
            <label for="remove-seats-select" class="block text-sm font-medium text-grey-700 mb-1">
              Reduce to
            </label>
            <div class="flex items-center gap-2">
              <select
                id="remove-seats-select"
                name="seats"
                required
                class="w-24 h-10 px-3 border border-grey-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-purple-600"
              >
                <%= for n <- max(@quantity - 1, 1)..max(@member_count, 1) do %>
                  <option value={n}>{n}</option>
                <% end %>
              </select>
              <span class="text-sm text-grey-600">
                seat(s) @ {BillingHelpers.plan_price(@plan_id)}
              </span>
            </div>
          </div>
        <% end %>
      </form>
      <:footer>
        <.button type="button" variant="secondary" phx-click={hide_modal("remove-seats-modal")}>
          Cancel
        </.button>
        <.button
          type="submit"
          form="remove-seats-form"
          variant="danger"
          disabled={@quantity <= @member_count}
          onclick="this.disabled=true;this.form.submit();"
        >
          Remove seats
        </.button>
      </:footer>
    </.modal>
    """
  end

  attr :organization, :map, required: true
  attr :plan_id, :string, default: nil

  defp change_plan_modal(assigns) do
    ~H"""
    <.modal id="change-plan-modal" title="Change plan">
      <form
        id="change-plan-form"
        action={~p"/dashboard/orgs/#{@organization}/change-plan"}
        method="post"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input
          type="hidden"
          name="plan_id"
          value={
            if @plan_id == "organization-monthly",
              do: "organization-annually",
              else: "organization-monthly"
          }
        />
        <p class="text-sm text-grey-600">
          <%= if @plan_id == "organization-monthly" do %>
            Switch to the annual plan and save with <strong>{BillingHelpers.plan_price("organization-annually")} per user / year</strong>.
          <% else %>
            Switch to the monthly plan at <strong>{BillingHelpers.plan_price("organization-monthly")} per user / month</strong>.
          <% end %>
        </p>
      </form>
      <:footer>
        <.button type="button" variant="secondary" phx-click={hide_modal("change-plan-modal")}>
          Cancel
        </.button>
        <.button
          type="submit"
          form="change-plan-form"
          variant="primary"
          onclick="this.disabled=true;this.form.submit();"
        >
          Confirm
        </.button>
      </:footer>
    </.modal>
    """
  end
end

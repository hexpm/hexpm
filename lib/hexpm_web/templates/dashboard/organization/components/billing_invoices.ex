defmodule HexpmWeb.Dashboard.Organization.Components.BillingInvoices do
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  alias HexpmWeb.Dashboard.Organization.Components.BillingHelpers
  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Table, only: [table: 1]

  attr :current_user, :map, required: true
  attr :organization, :map, required: true
  attr :invoices, :list, default: []
  attr :card, :map, default: nil
  attr :subscription, :map, default: nil
  attr :stripe_publishable_key, :string, default: nil

  def billing_invoices(assigns) do
    ~H"""
    <%= if @invoices && @invoices != [] do %>
      <div class="bg-white border border-grey-200 rounded-lg overflow-hidden">
        <div class="px-6 py-5 border-b border-grey-200">
          <h2 class="text-grey-900 text-lg font-semibold">Payment history</h2>
        </div>
        <div class="px-6">
          <.table>
            <:header>
              <th class="px-0 py-3 text-left text-sm font-medium text-grey-500">Date</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">Amount</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">Payment</th>
              <th class="px-4 py-3 text-left text-sm font-medium text-grey-500">Status</th>
            </:header>
            <:row :for={invoice <- @invoices}>
              <.invoice_row
                current_user={@current_user}
                invoice={invoice}
                organization={@organization}
                card={@card}
                subscription={@subscription}
                stripe_publishable_key={@stripe_publishable_key}
              />
            </:row>
          </.table>
        </div>
      </div>
    <% end %>
    """
  end

  attr :current_user, :map, required: true
  attr :invoice, :map, required: true
  attr :organization, :map, required: true
  attr :card, :map, default: nil
  attr :subscription, :map, default: nil
  attr :stripe_publishable_key, :string, default: nil

  defp invoice_row(assigns) do
    ~H"""
    <tr>
      <td class="px-0 py-4 whitespace-nowrap text-grey-900">
        <%= if @invoice["id"] do %>
          <a
            href={~p"/dashboard/orgs/#{@organization}/invoices/#{@invoice["id"]}"}
            target="_blank"
            rel="noopener"
            class="text-purple-600 hover:text-purple-700 hover:underline"
          >
            {BillingHelpers.payment_date(@invoice["date"] || @invoice["created"])}
          </a>
        <% else %>
          {BillingHelpers.payment_date(@invoice["date"] || @invoice["created"])}
        <% end %>
      </td>
      <td class="px-4 py-4 whitespace-nowrap text-grey-900">
        {BillingHelpers.dollar_money(!!@invoice["refund"], @invoice["amount_due"])}
      </td>
      <td class="px-4 py-4 whitespace-nowrap text-grey-600">
        {BillingHelpers.payment_card(@invoice["card"])}
      </td>
      <td class="px-4 py-4 whitespace-nowrap">
        {invoice_status(@invoice, @organization, @card, @subscription, @current_user)}
      </td>
    </tr>
    """
  end

  defp invoice_status(%{"refund" => true, "status" => "succeeded"}, _, _, _, _), do: "Refund Paid"

  defp invoice_status(%{"refund" => true, "status" => s}, _, _, _, _)
       when s in ["failed", "canceled"],
       do: "Refund Canceled"

  defp invoice_status(%{"refund" => true, "status" => s}, _, _, _, _)
       when s in ["pending", "requires_action"],
       do: "Refund Pending"

  defp invoice_status(%{"paid" => true}, _, _, _, _), do: "Paid"
  defp invoice_status(%{"status" => "uncollectible"}, _, _, _, _), do: "Forgiven"
  defp invoice_status(%{"paid" => false, "attempted" => false}, _, _, _, _), do: "Pending"

  defp invoice_status(%{"paid" => false, "attempted" => true}, _, nil, _, _) do
    assigns = %{}

    ~H"""
    <span class="text-grey-400 italic" title="No payment method on file">Pay now</span>
    """
  end

  defp invoice_status(%{"paid" => false, "attempted" => true}, _, _card, %{"status" => status}, _)
       when status in ["incomplete_expired", "canceled"] do
    assigns = %{}

    ~H"""
    <span class="text-grey-400 italic" title="Subscription is not active">Pay now</span>
    """
  end

  defp invoice_status(
         %{
           "paid" => false,
           "attempted" => true,
           "payment_intent_client_secret" => client_secret,
           "payment_method" => payment_method
         },
         _org,
         _card,
         _subscription,
         _current_user
       )
       when is_binary(client_secret) do
    assigns = %{client_secret: client_secret, payment_method: payment_method}

    ~H"""
    <button
      type="button"
      class="sca-pay-button text-sm font-medium text-amber-700 bg-amber-50 border border-amber-200 px-3 py-1.5 rounded-lg hover:bg-amber-100 transition-colors"
      data-client-secret={@client_secret}
      data-payment-method={@payment_method}
    >
      Authenticate payment
    </button>
    """
  end

  defp invoice_status(
         %{"paid" => false, "attempted" => true, "id" => inv_id},
         org,
         _card,
         _sub,
         current_user
       ) do
    assigns = %{inv_id: inv_id, org: org, current_user: current_user}

    ~H"""
    <.sudo_form
      current_user={@current_user}
      action={~p"/dashboard/orgs/#{@org}/invoices/#{@inv_id}/pay"}
      class="inline"
    >
      <.button type="submit" variant="primary" size="sm">Pay now</.button>
    </.sudo_form>
    """
  end

  defp invoice_status(%{"paid" => false, "attempted" => true}, _, _, _, _), do: "Payment Failed"
  defp invoice_status(_, _, _, _, _), do: ""
end

defmodule HexpmWeb.Dashboard.Organization.Components.BillingInvoices do
  use Phoenix.Component
  use PhoenixHTMLHelpers

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  alias HexpmWeb.Dashboard.Organization.Components.BillingHelpers
  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Table, only: [table: 1]

  attr :organization, :map, required: true
  attr :invoices, :list, default: []
  attr :card, :map, default: nil

  def billing_invoices(assigns) do
    ~H"""
    <%= if @invoices && @invoices != [] do %>
      <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:overflow-hidden">
        <div class="tw:px-6 tw:py-5 tw:border-b tw:border-grey-200">
          <h2 class="tw:text-grey-900 tw:text-lg tw:font-semibold">Payment history</h2>
        </div>
        <div class="tw:px-6">
          <.table>
            <:header>
              <th class="tw:px-0 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">Date</th>
              <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">Amount</th>
              <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">Payment</th>
              <th class="tw:px-4 tw:py-3 tw:text-left tw:text-sm tw:font-medium tw:text-grey-500">Status</th>
            </:header>
            <:row :for={invoice <- @invoices}>
              <.invoice_row invoice={invoice} organization={@organization} card={@card} />
            </:row>
          </.table>
        </div>
      </div>
    <% end %>
    """
  end

  attr :invoice, :map, required: true
  attr :organization, :map, required: true
  attr :card, :map, default: nil

  defp invoice_row(assigns) do
    ~H"""
    <td class="tw:px-0 tw:py-4 tw:whitespace-nowrap tw:text-grey-900">
      <%= if @invoice["id"] do %>
        <a href={~p"/dashboard/orgs/#{@organization}/invoices/#{@invoice["id"]}"}
          target="_blank"
          rel="noopener"
          class="tw:text-purple-600 tw:hover:text-purple-700 tw:hover:underline">
          {BillingHelpers.payment_date(@invoice["date"] || @invoice["created"])}
        </a>
      <% else %>
        {BillingHelpers.payment_date(@invoice["date"] || @invoice["created"])}
      <% end %>
    </td>
    <td class="tw:px-4 tw:py-4 tw:whitespace-nowrap tw:text-grey-900">
      {BillingHelpers.dollar_money(!!@invoice["refund"], @invoice["amount_due"])}
    </td>
    <td class="tw:px-4 tw:py-4 tw:whitespace-nowrap tw:text-grey-600">
      {BillingHelpers.payment_card(@invoice["card"])}
    </td>
    <td class="tw:px-4 tw:py-4 tw:whitespace-nowrap">
      {invoice_status(@invoice, @organization, @card)}
    </td>
    """
  end

  defp invoice_status(%{"refund" => true, "status" => "succeeded"}, _, _), do: "Refund Paid"

  defp invoice_status(%{"refund" => true, "status" => s}, _, _)
       when s in ["failed", "canceled"],
       do: "Refund Canceled"

  defp invoice_status(%{"refund" => true, "status" => s}, _, _)
       when s in ["pending", "requires_action"],
       do: "Refund Pending"

  defp invoice_status(%{"paid" => true}, _, _), do: "Paid"
  defp invoice_status(%{"status" => "uncollectible"}, _, _), do: "Forgiven"
  defp invoice_status(%{"paid" => false, "attempted" => false}, _, _), do: "Pending"

  defp invoice_status(%{"paid" => false, "attempted" => true}, _, nil) do
    assigns = %{}

    ~H"""
    <span class="tw:text-grey-400 tw:italic" title="No payment method on file">Pay now</span>
    """
  end

  defp invoice_status(%{"paid" => false, "attempted" => true, "id" => inv_id}, org, _card) do
    assigns = %{inv_id: inv_id, org: org}

    ~H"""
    <form action={~p"/dashboard/orgs/#{@org}/invoices/#{@inv_id}/pay"} method="post" class="tw:inline">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <.button type="submit" variant="primary" size="sm">Pay now</.button>
    </form>
    """
  end

  defp invoice_status(%{"paid" => false, "attempted" => true}, _, _), do: "Payment Failed"
  defp invoice_status(_, _, _), do: ""
end

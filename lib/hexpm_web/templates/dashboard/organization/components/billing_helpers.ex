defmodule HexpmWeb.Dashboard.Organization.Components.BillingHelpers do
  import Phoenix.HTML, only: [raw: 1]
  import HexpmWeb.ViewHelpers, only: [pretty_date: 1]

  def plan(plan_id, unit_amount \\ nil)

  def plan("organization-monthly", unit_amount),
    do:
      "Organization, monthly billed (#{plan_price("organization-monthly", unit_amount)} per user / month)"

  def plan("organization-annually", unit_amount),
    do:
      "Organization, annually billed (#{plan_price("organization-annually", unit_amount)} per user / year)"

  def plan(_, unit_amount), do: plan("organization-monthly", unit_amount)

  def plan_price(plan_id, unit_amount \\ nil)

  def plan_price(_plan_id, unit_amount) when is_integer(unit_amount),
    do: dollar_money(unit_amount)

  def plan_price("organization-monthly", nil), do: "$9.00"
  def plan_price("organization-annually", nil), do: "$90.00"
  def plan_price(_, nil), do: "$9.00"

  def plan_interval("organization-annually"), do: "year"
  def plan_interval(_), do: "month"

  def payment_date(nil), do: ""

  def payment_date(unix) when is_integer(unix) do
    unix |> DateTime.from_unix!() |> DateTime.to_naive() |> pretty_date()
  end

  def payment_date(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} -> datetime |> DateTime.to_naive() |> pretty_date()
      {:error, _} -> iso_string |> NaiveDateTime.from_iso8601!() |> pretty_date()
    end
  end

  def money(nil), do: "0.00"

  def money(int) when is_integer(int) and int >= 0 do
    whole = div(int, 100)
    frac = rem(int, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{whole}.#{frac}"
  end

  def dollar_money(int), do: "$#{money(int)}"

  def dollar_money(negative?, int) when is_boolean(negative?) do
    "#{if negative?, do: "-", else: ""}#{dollar_money(int)}"
  end

  @no_card "No payment method on file"

  def payment_card(nil), do: @no_card
  def payment_card(%{"brand" => nil}), do: @no_card
  def payment_card(%{"last4" => nil}), do: @no_card

  def payment_card(card) do
    brand = Map.get(card, "brand", "Card")
    last4 = Map.get(card, "last4", "????")
    month = card |> Map.get("exp_month", "?") |> to_string() |> String.pad_leading(2, "0")
    year = Map.get(card, "exp_year", "????")
    "#{brand} **** **** **** #{last4}, Expires: #{month}/#{year}"
  end

  def payment_method(_card, true = _bank_transfer),
    do: "Bank transfer, invoices are due in 30 days"

  def payment_method(card, _bank_transfer), do: payment_card(card)

  def invoice_payment(%{"bank_transfer" => true}), do: "Bank transfer"
  def invoice_payment(invoice), do: payment_card(invoice["card"])

  def invoice_due_status(due_date) do
    {:ok, due_date, _offset} = DateTime.from_iso8601(due_date)

    if DateTime.compare(due_date, DateTime.utc_now()) == :lt,
      do: "Overdue",
      else: "Due #{due_date |> DateTime.to_naive() |> pretty_date()}"
  end

  # Bank account details from Stripe funding instructions, as a list of
  # `{title, [{label, value}]}` for each way the customer can transfer money
  def bank_transfer_details(%{"bank_transfer" => %{"financial_addresses" => addresses}}) do
    addresses
    |> Enum.flat_map(&financial_address/1)
    |> Enum.map(fn {title, rows} -> {title, Enum.reject(rows, &(elem(&1, 1) in [nil, ""]))} end)
  end

  def bank_transfer_details(nil), do: []

  defp financial_address(%{"type" => "aba", "aba" => aba}) do
    [
      {"US domestic transfer (ACH or wire)",
       [
         {"Account holder", aba["account_holder_name"]},
         {"Account holder address", bank_address(aba["account_holder_address"])},
         {"Bank", aba["bank_name"]},
         {"Bank address", bank_address(aba["bank_address"])},
         {"Routing number", aba["routing_number"]},
         {"Account number", aba["account_number"]}
       ]}
    ]
  end

  defp financial_address(%{"type" => "swift", "swift" => swift}) do
    [
      {"International wire (SWIFT)",
       [
         {"Account holder", swift["account_holder_name"]},
         {"Account holder address", bank_address(swift["account_holder_address"])},
         {"Bank", swift["bank_name"]},
         {"Bank address", bank_address(swift["bank_address"])},
         {"SWIFT code", swift["swift_code"]},
         {"Account number", swift["account_number"]}
       ]}
    ]
  end

  defp financial_address(_address), do: []

  defp bank_address(nil), do: nil

  defp bank_address(address) do
    [
      address["line1"],
      address["line2"],
      address["city"],
      Enum.join(Enum.reject([address["state"], address["postal_code"]], &is_nil/1), " "),
      address["country"]
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  # Short label for pill badges — single line, no HTML
  def subscription_badge_label(%{"status" => "active", "cancel_at_period_end" => false}),
    do: "Active"

  def subscription_badge_label(%{"status" => "active", "cancel_at_period_end" => true}),
    do: "Cancels at period end"

  def subscription_badge_label(%{"status" => "trialing"}), do: "Trialing"
  def subscription_badge_label(%{"status" => "past_due"}), do: "Past due"
  def subscription_badge_label(%{"status" => "incomplete"}), do: "Incomplete"
  def subscription_badge_label(%{"status" => "canceled"}), do: "Canceled"
  def subscription_badge_label(%{"status" => "incomplete_expired"}), do: "Expired"
  def subscription_badge_label(_), do: ""

  # Full prose for the status detail row — may include HTML via raw/1
  def subscription_status(
        %{"status" => "active", "cancel_at_period_end" => false},
        _card,
        _bank_transfer
      ),
      do: "Active"

  def subscription_status(
        %{"status" => "active", "cancel_at_period_end" => true},
        _card,
        _bank_transfer
      ),
      do: "Ends after current subscription period"

  def subscription_status(
        %{"status" => "trialing", "trial_end" => trial_end},
        card,
        bank_transfer
      ) do
    raw("Trial ends on #{payment_date(trial_end)}, #{trial_status_message(card, bank_transfer)}")
  end

  def subscription_status(%{"status" => "past_due"}, _card, _bank_transfer),
    do: "Active with past due invoice — if unpaid the organization will be disabled"

  def subscription_status(%{"status" => "incomplete"}, _card, _bank_transfer), do: "Incomplete"
  def subscription_status(%{"status" => "canceled"}, _card, _bank_transfer), do: "Not active"

  def subscription_status(%{"status" => "incomplete_expired"}, _card, _bank_transfer),
    do: "Not active"

  def subscription_status(nil, _card, _bank_transfer), do: ""
  def subscription_status(_subscription, _card, _bank_transfer), do: ""

  def discount_status(nil), do: ""

  def discount_status(%{"name" => name, "percent_off" => pct}),
    do: "(\"#{name}\" discount for #{pct}% of price)"

  def proration_description("organization-monthly", price, days, qty, qty, _bank_transfer) do
    raw("""
    Each new seat will be prorated on the next invoice for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description("organization-annually", price, days, qty, qty, bank_transfer) do
    raw("""
    Each new seat will be #{proration_charge(bank_transfer)} for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description("organization-monthly", price, days, qty, max_qty, _bank_transfer)
      when is_integer(qty) and is_integer(max_qty) and qty < max_qty do
    raw("""
    You have already used <strong>#{max_qty}</strong> seats this billing period.
    New seats over this amount will be prorated for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description("organization-annually", price, days, qty, max_qty, bank_transfer)
      when is_integer(qty) and is_integer(max_qty) and qty < max_qty do
    raw("""
    You have already used <strong>#{max_qty}</strong> seats this billing period.
    New seats over this amount will be #{proration_charge(bank_transfer)} for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description(_, _, _, _, _, _), do: ""

  defp proration_charge(true = _bank_transfer),
    do: "invoiced a proration, payable by bank transfer,"

  defp proration_charge(_bank_transfer), do: "charged a proration"

  def default_billing_emails(user, billing_email) do
    emails = user.emails |> Enum.filter(& &1.verified) |> Enum.map(& &1.email)
    [billing_email | emails] |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  def show_person?(person, errors), do: (person || errors["person"]) && !errors["company"]
  def show_company?(company, errors), do: (company || errors["company"]) && !errors["person"]

  @trial_no_card """
  your subscription will end after the trial period because we have no payment method on file.
  Please add a payment method to continue using organizations after the trial.
  """

  defp trial_status_message(_card, true = _bank_transfer),
    do: "an invoice with bank transfer details is sent when the trial ends"

  defp trial_status_message(%{"brand" => nil}, _bank_transfer), do: @trial_no_card
  defp trial_status_message(nil, _bank_transfer), do: @trial_no_card

  defp trial_status_message(_card, _bank_transfer),
    do: "a payment method is on file and your subscription will continue after the trial"
end

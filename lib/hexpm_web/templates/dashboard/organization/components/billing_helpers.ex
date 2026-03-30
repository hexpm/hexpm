defmodule HexpmWeb.Dashboard.Organization.Components.BillingHelpers do
  import Phoenix.HTML, only: [raw: 1]
  import HexpmWeb.ViewHelpers, only: [pretty_date: 1]

  def plan("organization-monthly"), do: "Organization, monthly billed ($7.00 per user / month)"
  def plan("organization-annually"), do: "Organization, annually billed ($70.00 per user / year)"
  def plan(_), do: "Organization, monthly billed ($7.00 per user / month)"

  def plan_price("organization-monthly"), do: "$7.00"
  def plan_price("organization-annually"), do: "$70.00"
  def plan_price(_), do: "$7.00"

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
  def subscription_status(%{"status" => "active", "cancel_at_period_end" => false}, _card),
    do: "Active"

  def subscription_status(%{"status" => "active", "cancel_at_period_end" => true}, _card),
    do: "Ends after current subscription period"

  def subscription_status(%{"status" => "trialing", "trial_end" => trial_end}, card) do
    raw("Trial ends on #{payment_date(trial_end)}, #{trial_status_message(card)}")
  end

  def subscription_status(%{"status" => "past_due"}, _card),
    do: "Active with past due invoice — if unpaid the organization will be disabled"

  def subscription_status(%{"status" => "incomplete"}, _card), do: "Incomplete"
  def subscription_status(%{"status" => "canceled"}, _card), do: "Not active"
  def subscription_status(%{"status" => "incomplete_expired"}, _card), do: "Not active"
  def subscription_status(nil, _card), do: ""
  def subscription_status(_subscription, _card), do: ""

  def discount_status(nil), do: ""

  def discount_status(%{"name" => name, "percent_off" => pct}),
    do: "(\"#{name}\" discount for #{pct}% of price)"

  def proration_description("organization-monthly", price, days, qty, qty) do
    raw("""
    Each new seat will be prorated on the next invoice for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description("organization-annually", price, days, qty, qty) do
    raw("""
    Each new seat will be charged a proration for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description("organization-monthly", price, days, qty, max_qty)
      when is_integer(qty) and is_integer(max_qty) and qty < max_qty do
    raw("""
    You have already used <strong>#{max_qty}</strong> seats this billing period.
    New seats over this amount will be prorated for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description("organization-annually", price, days, qty, max_qty)
      when is_integer(qty) and is_integer(max_qty) and qty < max_qty do
    raw("""
    You have already used <strong>#{max_qty}</strong> seats this billing period.
    New seats over this amount will be charged a proration for
    <strong>#{days}</strong> day(s) @ <strong>$#{money(price)}</strong>.
    """)
  end

  def proration_description(_, _, _, _, _), do: ""

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

  defp trial_status_message(%{"brand" => nil}), do: @trial_no_card
  defp trial_status_message(nil), do: @trial_no_card

  defp trial_status_message(_card),
    do: "a payment method is on file and your subscription will continue after the trial"
end

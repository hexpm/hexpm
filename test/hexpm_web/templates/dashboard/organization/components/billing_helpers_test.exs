defmodule HexpmWeb.Dashboard.Organization.Components.BillingHelpersTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Dashboard.Organization.Components.BillingHelpers

  describe "payment_date/1" do
    test "returns empty string for nil" do
      assert BillingHelpers.payment_date(nil) == ""
    end

    test "formats a unix timestamp" do
      # 2024-01-15 10:30:00 UTC
      unix = ~U[2024-01-15 10:30:00Z] |> DateTime.to_unix()
      result = BillingHelpers.payment_date(unix)
      assert result =~ "2024"
      assert is_binary(result)
    end

    test "formats a plain ISO8601 string (no timezone)" do
      result = BillingHelpers.payment_date("2024-01-15T10:30:00")
      assert result =~ "2024"
      assert is_binary(result)
    end

    test "handles a timezone-aware ISO8601 string without crashing" do
      result = BillingHelpers.payment_date("2024-01-15T10:30:00Z")
      assert result =~ "2024"
      assert is_binary(result)
    end

    test "handles a positive UTC offset ISO8601 string" do
      result = BillingHelpers.payment_date("2024-06-01T12:00:00+02:00")
      assert result =~ "2024"
      assert is_binary(result)
    end
  end

  describe "payment_card/1" do
    test "returns no-card message for nil" do
      assert BillingHelpers.payment_card(nil) == "No payment method on file"
    end

    test "returns no-card message when brand is nil" do
      assert BillingHelpers.payment_card(%{"brand" => nil}) == "No payment method on file"
    end

    test "returns no-card message when last4 is nil" do
      assert BillingHelpers.payment_card(%{"last4" => nil}) == "No payment method on file"
    end

    test "formats a complete card" do
      card = %{"brand" => "Visa", "last4" => "4242", "exp_month" => 12, "exp_year" => 2028}
      assert BillingHelpers.payment_card(card) == "Visa **** **** **** 4242, Expires: 12/2028"
    end

    test "pads single-digit exp_month" do
      card = %{"brand" => "Visa", "last4" => "4242", "exp_month" => 3, "exp_year" => 2028}
      assert BillingHelpers.payment_card(card) =~ "Expires: 03/2028"
    end

    test "uses safe defaults when card fields are missing" do
      result = BillingHelpers.payment_card(%{})
      # exp_month "?" is pad_leading'd to "0?" — expected behaviour
      assert result == "Card **** **** **** ????, Expires: 0?/????"
    end
  end

  describe "money/1" do
    test "formats cents to dollars" do
      assert BillingHelpers.money(700) == "7.00"
      assert BillingHelpers.money(1050) == "10.50"
      assert BillingHelpers.money(0) == "0.00"
    end

    test "pads single-digit cents" do
      assert BillingHelpers.money(701) == "7.01"
    end

    test "returns 0.00 for nil" do
      assert BillingHelpers.money(nil) == "0.00"
    end
  end

  describe "plan pricing" do
    test "uses the current catalog price for new subscriptions and plan switches" do
      assert BillingHelpers.plan_price("organization-monthly") == "$9.00"
      assert BillingHelpers.plan_price("organization-annually") == "$90.00"
    end

    test "uses the API-provided effective amount for an existing subscription" do
      assert BillingHelpers.plan_price("organization-monthly", 700) == "$7.00"

      assert BillingHelpers.plan("organization-monthly", 700) ==
               "Organization, monthly billed ($7.00 per user / month)"
    end
  end

  describe "subscription_badge_label/1" do
    test "active non-cancelling subscription" do
      assert BillingHelpers.subscription_badge_label(%{
               "status" => "active",
               "cancel_at_period_end" => false
             }) == "Active"
    end

    test "active but scheduled to cancel" do
      assert BillingHelpers.subscription_badge_label(%{
               "status" => "active",
               "cancel_at_period_end" => true
             }) == "Cancels at period end"
    end

    test "trialing" do
      assert BillingHelpers.subscription_badge_label(%{"status" => "trialing"}) == "Trialing"
    end

    test "past_due" do
      assert BillingHelpers.subscription_badge_label(%{"status" => "past_due"}) == "Past due"
    end

    test "unknown status returns empty string" do
      assert BillingHelpers.subscription_badge_label(%{"status" => "unknown_future_status"}) == ""
      assert BillingHelpers.subscription_badge_label(nil) == ""
    end
  end

  describe "subscription_status/3" do
    test "nil subscription returns empty string" do
      assert BillingHelpers.subscription_status(nil, nil, false) == ""
    end

    test "unknown status returns empty string without crashing" do
      assert BillingHelpers.subscription_status(%{"status" => "paused"}, nil, false) == ""
    end

    test "trialing with timezone-aware trial_end does not crash" do
      sub = %{"status" => "trialing", "trial_end" => "2024-04-12T00:00:00Z"}
      result = BillingHelpers.subscription_status(sub, nil, false)
      assert inspect(result) =~ "Trial ends on"
    end

    test "trialing with unix timestamp trial_end does not crash" do
      trial_end = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix()
      sub = %{"status" => "trialing", "trial_end" => trial_end}
      result = BillingHelpers.subscription_status(sub, nil, false)
      assert inspect(result) =~ "Trial ends on"
    end

    test "trialing without card says the subscription ends after the trial" do
      sub = %{"status" => "trialing", "trial_end" => "2024-04-12T00:00:00Z"}
      result = BillingHelpers.subscription_status(sub, nil, false)
      assert inspect(result) =~ "your subscription will end after the trial period"
    end

    test "trialing with bank transfer says an invoice is sent" do
      sub = %{"status" => "trialing", "trial_end" => "2024-04-12T00:00:00Z"}
      result = BillingHelpers.subscription_status(sub, nil, true)

      assert inspect(result) =~
               "an invoice with bank transfer details is sent when the trial ends"
    end
  end

  describe "payment_method/2" do
    test "bank transfer" do
      assert BillingHelpers.payment_method(nil, true) ==
               "Bank transfer, invoices are due in 30 days"
    end

    test "card" do
      card = %{"brand" => "Visa", "last4" => "4242", "exp_month" => 1, "exp_year" => 2030}

      assert BillingHelpers.payment_method(card, false) ==
               "Visa **** **** **** 4242, Expires: 01/2030"
    end
  end

  describe "invoice_payment/1" do
    test "bank transfer invoice" do
      assert BillingHelpers.invoice_payment(%{"bank_transfer" => true, "card" => nil}) ==
               "Bank transfer"
    end

    test "card invoice" do
      invoice = %{"bank_transfer" => false, "card" => %{"brand" => nil}}
      assert BillingHelpers.invoice_payment(invoice) == "No payment method on file"
    end
  end

  describe "invoice_due_status/1" do
    test "due in the future" do
      due_date = DateTime.utc_now() |> DateTime.add(10, :day)
      expected = "Due #{due_date |> DateTime.to_naive() |> HexpmWeb.ViewHelpers.pretty_date()}"
      assert BillingHelpers.invoice_due_status(DateTime.to_iso8601(due_date)) == expected
    end

    test "past due date" do
      assert BillingHelpers.invoice_due_status("2024-04-12T00:00:00.000000Z") == "Overdue"
    end
  end

  describe "bank_transfer_details/1" do
    test "lists the domestic and international bank details" do
      funding_instructions = %{
        "bank_transfer" => %{
          "financial_addresses" => [
            %{
              "type" => "aba",
              "aba" => %{
                "account_holder_name" => "Hex",
                "account_holder_address" => %{
                  "line1" => "354 Oyster Point Blvd",
                  "line2" => nil,
                  "city" => "South San Francisco",
                  "state" => "CA",
                  "postal_code" => "94080",
                  "country" => "US"
                },
                "account_number" => "11119934683455685",
                "bank_name" => "US Test Bank",
                "routing_number" => "999999999"
              }
            },
            %{
              "type" => "swift",
              "swift" => %{
                "account_holder_name" => "Hex",
                "account_number" => "11119934683455685",
                "bank_name" => "US Test Bank",
                "swift_code" => "TESTUS99XXX"
              }
            },
            %{"type" => "unknown"}
          ]
        }
      }

      assert [
               {"US domestic transfer (ACH or wire)", aba},
               {"International wire (SWIFT)", swift}
             ] = BillingHelpers.bank_transfer_details(funding_instructions)

      assert {"Account holder address",
              "354 Oyster Point Blvd, South San Francisco, CA 94080, US"} in aba

      assert {"Routing number", "999999999"} in aba
      assert {"SWIFT code", "TESTUS99XXX"} in swift
      refute List.keymember?(swift, "Bank address", 0)
    end

    test "nil funding instructions" do
      assert BillingHelpers.bank_transfer_details(nil) == []
    end
  end
end

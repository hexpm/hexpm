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

  describe "subscription_status/2" do
    test "nil subscription returns empty string" do
      assert BillingHelpers.subscription_status(nil, nil) == ""
    end

    test "unknown status returns empty string without crashing" do
      assert BillingHelpers.subscription_status(%{"status" => "paused"}, nil) == ""
    end

    test "trialing with timezone-aware trial_end does not crash" do
      sub = %{"status" => "trialing", "trial_end" => "2024-04-12T00:00:00Z"}
      result = BillingHelpers.subscription_status(sub, nil)
      assert inspect(result) =~ "Trial ends on"
    end

    test "trialing with unix timestamp trial_end does not crash" do
      trial_end = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix()
      sub = %{"status" => "trialing", "trial_end" => trial_end}
      result = BillingHelpers.subscription_status(sub, nil)
      assert inspect(result) =~ "Trial ends on"
    end
  end
end

defmodule Hexpm.Billing.Local do
  @behaviour Hexpm.Billing.Behaviour

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  def checkout(_organization, _data) do
    {:ok, %{}}
  end

  def get(_organization, _opts \\ []) do
    # Realistic stub data for local development — allows the billing UI to be
    # reviewed without a running billing service. Safe: this module is only
    # used in dev (see config/config.exs). Production uses Billing.Hexpm.
    # Note: create/1 and update/2 are no-ops, so form submissions don't persist locally.
    now = DateTime.utc_now()
    period_end = now |> DateTime.add(30, :day) |> DateTime.to_unix()
    last_month = now |> DateTime.add(-30, :day) |> DateTime.to_unix()

    %{
      "checkout_html" => "",
      "monthly_cost" => 700,
      "email" => "billing@example.com",
      "plan_id" => "organization-monthly",
      "quantity" => 1,
      "subscription" => %{
        "status" => "active",
        "cancel_at_period_end" => false,
        "current_period_end" => period_end,
        "trial_end" => nil
      },
      "card" => %{
        "brand" => "Visa",
        "last4" => "4242",
        "exp_month" => 12,
        "exp_year" => 2028
      },
      "amount_with_tax" => 700,
      "tax_rate" => 0,
      "person" => %{
        "country" => "PT"
      },
      "company" => nil,
      "invoices" => [
        %{
          "id" => "inv_local_001",
          "date" => last_month,
          "created" => last_month,
          "amount_due" => 1400,
          "paid" => true,
          "attempted" => true,
          "refund" => false,
          "status" => "succeeded",
          "card" => %{"brand" => "Visa", "last4" => "4242"}
        }
      ]
    }
  end

  def cancel(_organization) do
    %{}
  end

  def resume(_organization) do
    {:ok, %{}}
  end

  def create(_params) do
    {:ok, %{}}
  end

  def update(_organization, _params) do
    {:ok, %{}}
  end

  def void_invoice(_organization, _payments_token) do
    :ok
  end

  def change_plan(_organization, _params) do
    :ok
  end

  def invoice(_id, _opts \\ []) do
    %{}
  end

  def pay_invoice(_id) do
    :ok
  end

  def report() do
    []
  end
end

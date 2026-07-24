defmodule Hexpm.Billing.Local do
  @behaviour Hexpm.Billing.Behaviour

  alias Hexpm.Accounts.Organizations
  alias Hexpm.Repo

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  def checkout(_organization, _data) do
    {:ok, %{}}
  end

  def get(organization, _opts \\ []) do
    # Realistic stub data for local development — allows the billing UI to be
    # reviewed without a running billing service. Safe: this module is only
    # used in dev (see config/config.exs). Production uses Billing.Hexpm.
    now = DateTime.utc_now()
    period_end = now |> DateTime.add(60, :day) |> DateTime.to_unix()
    last_month = now |> DateTime.add(-30, :day) |> DateTime.to_unix()

    %{
      "checkout_html" => "",
      "monthly_cost" => 700,
      "email" => "billing@example.com",
      "plan_id" => "organization-monthly",
      "plan_unit_amount" => 700,
      "pending_plan_unit_amount" => 900,
      "plan_price_change_at" => period_end,
      "quantity" => quantity(organization),
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

  def update(organization, %{"quantity" => quantity}) when is_integer(quantity) do
    if organization_record = Organizations.get(organization) do
      organization_record
      |> Ecto.Changeset.change(billing_seats: quantity)
      |> Repo.update!()
    end

    {:ok, get(organization)}
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

  defp quantity(organization) do
    case Organizations.get(organization) do
      %{billing_seats: quantity} when is_integer(quantity) -> quantity
      _organization -> 1
    end
  end
end

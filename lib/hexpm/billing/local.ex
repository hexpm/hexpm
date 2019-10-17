defmodule Hexpm.Billing.Local do
  @behaviour Hexpm.Billing

  def checkout(_organization, _data) do
    {:ok, %{}}
  end

  def get(_organization) do
    %{
      "checkout_html" => "",
      "monthly_cost" => 800,
      "invoices" => []
    }
  end

  def cancel(_organization) do
    %{}
  end

  def create(_params) do
    {:ok, %{}}
  end

  def update(_organization, _params) do
    {:ok, %{}}
  end

  def change_plan(_organization, _params) do
    :ok
  end

  def invoice(_id) do
    %{}
  end

  def pay_invoice(_id) do
    :ok
  end

  def report() do
    []
  end
end

defmodule Hexpm.Billing.Local do
  @behaviour Hexpm.Billing

  def checkout(_repository, _data) do
    %{}
  end

  def dashboard(_repository) do
    %{
      "checkout_html" => "",
      "monthly_cost" => 800,
      "invoices" => []
    }
  end

  def cancel(_repository) do
    %{}
  end

  def invoice(_id) do
    %{}
  end

  def report() do
    []
  end
end

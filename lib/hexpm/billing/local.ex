defmodule Hexpm.Billing.Local do
  @behaviour Hexpm.Billing

  def dashboard(_repository) do
    %{
      "checkout_html" => "",
      "monthly_cost" => 800,
      "invoices" => []
    }
  end

  def invoice(_id) do
    %{}
  end

  def checkout(_repository, _data) do
    %{}
  end
end
